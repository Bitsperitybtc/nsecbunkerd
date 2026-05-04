release:
	pnpm build
	echo '#!/usr/bin/env node' | cat - dist/client.js > dist/client-temp.js && mv dist/client-temp.js dist/client.js
	pnpm publish --no-git-checks

docker:
	docker build --no-cache -t ghcr.io/bitsperitybtc/nsecbunkerd:latest .
	docker push ghcr.io/bitsperitybtc/nsecbunkerd:latest