#
BUILD = staging

.PHONY: pack

.DEFAULT: pack

.SUFFIXES:
.SUFFIXES: .json

pack: .$(BUILD)
	@cat .$(BUILD)

.$(BUILD): $(BUILD).json $(BUILD)_variables.json
	@( packer build -var-file=$(BUILD)_variables.json -var ssh_private_key_file=${HOME}/.ssh/zozo.pem -var aws_access_key=${AWS_ACCESS_KEY_ID} -var aws_secret_key=${AWS_SECRET_ACCESS_KEY} $(BUILD).json \
	| tee .$(BUILD).out ) && tail -n 1 .$(BUILD).out > .$(BUILD)
