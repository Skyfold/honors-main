EXECUTABLES  := kops kubectl
K := $(foreach exec,$(EXECUTABLES),\
        $(if $(shell which $(exec)),$(exec),$(error "No $(exec) in PATH)))

default: deployment

init: check-env
	kops create cluster \
				--yes \
				--zones $(ZONES) \
				--ssh-public-key $(PUBLIC_KEY_PATH) \
				$(NAME)
	# run make setup when make status shows the cluster is live

setup: check-env
	# Run make setup first and wait 20min
	# 
	# Note: run kubectl proxy to access the dashboard
	#
	# This is meant to be only run once after
	# make status shows that the cluster is up
	#
	# The inverse of setup is teardown
	$(MAKE) setup -C k8/postgresql
	$(MAKE) setup -C sqitch/realworld

status: check-env
	kops validate cluster
	$(MAKE) status -C k8/PostgREST

deployment: check-env
	$(MAKE) -C k8/ingress
	$(MAKE) deployment -C k8/postgresql
	# run make status to check if you can procede to
	# make deploy-PostgREST

deploy-PostgREST: check-env
	$(MAKE) -C sqitch/realworld
	$(MAKE) -C k8/PostgREST

clean: check-env
	$(MAKE) clean -C k8/ingress
	$(MAKE) clean -C k8/postgresql
	$(MAKE) clean -C k8/PostgREST

teardown:
	# Inverse of setup
	helm reset
	$(MAKE) remove -C sqitch/realworld

shutdown: check-env
	# This is the inverse of init
	kops delete cluster --yes $(NAME)

check-env:
ifndef ZONES
	$(error ZONES is undefined: source env)
endif
ifndef NAME
	$(error NAME is undefined: source env)
endif
ifndef PUBLIC_KEY_PATH
	$(error PUBLIC_KEY_PATH is undefined: source env)
endif

.PHONY: init teardown default deployment clean status shutdown check-env
