# The Farcaster Mini-App for Fan Tokens

Single-page app that is easy to host on cloudflare.

Blocks arrive every 2 seconds. We proably don't need the interface to update that quickly. Every minute is probably better for people's battery/network/rpc costs.

MVP:

1. Show the user's balance for my fan token on the Base Network (not yet deployed).
2. Show the fan token balance denominated in the underlying tokens. There is a blockchain query that makes this easy.
3. If the user has a balance, show a "Redeem" button to turn in fan tokens for either the pooltogether tickets, or the underlying tokens (the user can decide which).
4. "Start Deposit" button to turn pooltogether tickets or underlying tokens into a fan token. For complicated reasons, this requires a 3 day timer. The delay when starting should require a specific confirmation from the user.
5. "Finish Deposit" button to finalize a deposit after 3 days have passed. You can query the blockchain to see how long a deposit has until its ready.
6. "Share" buttons that create casts that link to a token or user's page.
7. A "force refresh" button in case someone doesn't want to wait a minute. Or maybe an "advanced" setting that lets the user pick how often to update the UI.
8. "Sponsor" toggle that makes it so any fan tokens you hold are not eligible for prizes. The owner of the fan token has this set on by default (they already get 50% of the interest, so it doesn't make sense to also pay them for holding tokens).

V1: 

1. A tab for launching your own fan tokens (users can have as many as they want). 
2. List of all the fan tokens that exist.
3. A list of all the prizes of that have been won recently. I think we can get this from the blockchain, but it might require a database. Needs more research, but the existing PoolTogether interfaces will probably be a good example to follow.

Less important pieces that I don't need yet, but I would like to add eventually:

1. "Start Deposit" button that allows depositing for another user.
2. "Finish Deposit" button that shows any deposits coming from any user. This will be hard to do without a database.
3. Support standard browsers. There are a ton of possible rpc providers. If the farcaster context isn't detected, we should use more traditional wallet libraries (see https://viem.sh/, https://eips.ethereum.org/EIPS/eip-6963, https://github.com/wevm/mipd). If someone visits the mini-app in a normal browser, you won't have their farcaster info, but you can still maybe connect to their wallet.
4. Transfer button to make it easy to send your fan tokens to another address.
5. Blockchain selector so that people can use more chains. Just Base is fine for now.

## Style

I like retro designs with subtle animations.

- [SpaceJam](https://www.spacejam.com/1996/)
- [System.css](https://sakofchit.github.io/system.css/)

Follow system settings for dark/light-mode.

## Libraries

There are a few SDKs for mini-app development. There are the two most popular:

- [Farcaster's](https://miniapps.farcaster.xyz/)
- [Coinbase's](https://www.base.org/build/mini-apps)
