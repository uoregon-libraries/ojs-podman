.PHONY: dedupe-user-settings

dedupe-user-settings:
	cd cmd/dedupe-user-settings && go build -o ../../bin/dedupe-user-settings

.PHONY: create-admin
create-admin:
	cd cmd/create-admin && go build -ldflags="-s -w" -o ../../bin/create-admin
