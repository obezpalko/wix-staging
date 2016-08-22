#
STATEBUCKET ?= wix-staging
AZ ?= c
STORE_REGION ?= us-west-2

AWS_PROFILE=wix_code
PARAMS=$(shell sed -E '1,/\[profile $(AWS_PROFILE)/d; /^\[/,$$d; /^[^a-zA-Z]/d; /^\s*$$/d;' < $${HOME}/.aws/config | awk -F= '{if($$1=="region"){print "AWS_REGION="$$2};printf("%s=%s ", toupper($$1),$$2) }')
$(shell export $(PARAMS))

PREFIX ?= .build
SHELL=/bin/sh

.PHONY: all plan apply push pull refresh destroy plan-destroy show graph

all: plan

init: $(PREFIX)/.init

$(PREFIX)/.init:
	export $(PARAMS) && \
		[ -d "$(PREFIX)/$${REGION}$(AZ)" ] || mkdir -p "$(PREFIX)/$${REGION}$(AZ)" && \
		ln -sf $(CURDIR)/*.tf $(PREFIX)/$${REGION}$(AZ)/ && \
		ln -sf $(CURDIR)/.chef $(PREFIX)/$${REGION}$(AZ)/ && \
		cd $(PREFIX)/$${REGION}$(AZ) && \
		terraform remote config -backend=s3 -backend-config="bucket=$(STATEBUCKET)" -backend-config="key=$${REGION}$(AZ).tfstate" \
			-backend-config="region=$(STORE_REGION)" | tee .init

pull push: $(PREFIX)/.init
	export $(PARAMS) && \
	cd $(PREFIX)/$${REGION}$(AZ) && \
	terraform remote $@

plan apply refresh destroy: $(PREFIX)/.init pull
	export $(PARAMS) && \
	cd $(PREFIX)/$${REGION}$(AZ) && \
	terraform $@ -var region=$${REGION} -var az=$(AZ)

plan-destroy: init
	export $(PARAMS) && \
	cd $(PREFIX)/$${REGION}$(AZ) && \
	terraform plan -destroy -var region=$${REGION} -var az=$(AZ)

graph show: $(PREFIX)/.init
	export $(PARAMS) && \
	cd $(PREFIX)/$${REGION}$(AZ) && \
	terraform $@

taint:
	export $(PARAMS) && \
	cd $(PREFIX)/$${REGION}$(AZ) && \
	terraform $@ null_resource.staging-instance.0

clean:
	find . -name .init -delete

test:
	@export $(PARAMS) &&  echo $${REGION}
