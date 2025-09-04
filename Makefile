.PHONY: all
all: dedupe-user-settings create-admin change-password

.PHONY: dedupe-user-settings
dedupe-user-settings:
	cd cmd/dedupe-user-settings && go build -ldflags="-s -w" -o ../../bin/dedupe-user-settings

.PHONY: create-admin
create-admin:
	cd cmd/create-admin && go build -ldflags="-s -w" -o ../../bin/create-admin

.PHONY: change-password
change-password:
	cd cmd/change-password && go build -ldflags="-s -w" -o ../../bin/change-password

.PHONY: clean
clean:
	rm -f bin/*
