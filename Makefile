.PHONY: dedupe-user-settings

dedupe-user-settings:
	cd cmd/dedupe-user-settings && go build -o ../../bin/dedupe-user-settings
