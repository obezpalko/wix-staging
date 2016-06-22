#
STATEBUCKET ?= wix-staging
REGION ?= us-west-2
AZ ?= b
PREFIX ?= .build/$(REGION)$(AZ)
STORE_REGION ?= us-west-2
.PHONY: all plan apply push pull refresh destroy plan-destroy show graph


DEFAULT: show

init: $(PREFIX)/.init

$(PREFIX)/.init:
	@[ -d "$(PREFIX)" ] || mkdir -p "$(PREFIX)"
	@ln -sf $(CURDIR)/*.tf $(PREFIX)/
	@ln -sf $(CURDIR)/.chef $(PREFIX)/
	cd $(PREFIX) && \
	AWS_REGION=$(STORE_REGION) terraform remote config -backend=s3 -backend-config="bucket=$(STATEBUCKET)" -backend-config="key=$(REGION)$(AZ).tfstate" \
		-backend-config="region=$(STORE_REGION)" | tee .init

pull push: $(PREFIX)/.init
	cd $(PREFIX) && AWS_REGION=$(REGION) terraform remote $@

plan apply refresh destroy: $(PREFIX)/.init pull
	cd $(PREFIX) && AWS_REGION=$(REGION) terraform $@ -var-file=$(CURDIR)/staging.tfvars -var region=$(REGION) -var az=$(AZ)

plan-destroy: init
	cd $(PREFIX) && AWS_REGION=$(REGION) terraform plan -destroy \
		-var-file=$(CURDIR)/staging.tfvars -var region=$(REGION) -var az=$(AZ)

show graph: $(PREFIX)/.init
	@cd $(PREFIX) && AWS_REGION=$(REGION) terraform $@

