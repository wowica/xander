# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Fix reading multiplexer messages on `Xander.Util.plex/1`. This fix properly
accounts for the Mode bit in the multiplexer which fixes the reading of
protocol ID.

- Fix multiplexer header for outgoing messages. Properly setting the Mode as 1
bit and the mini protocol ID as 15 bits.

## [v0.3.0](https://github.com/wowica/xander/releases/tag/v0.3.0) (2025-08-14)

### Added

- Initial support for ChainSync mini-protocol. 
 - Added `Xander.ChainSync` behaviour with support for 
 `handle_block` and `handle_rollback` callback functions.
 - Support for syncing from either the Conway era boundary, a specific slot and
 block hash, or the current known tip of the chain.
 - Decoding partial block information. Only block number and block body size are
 passed to the `handle_block` client, and slot_number and block_hash are
 passed to the `handle_rollback` callback.

## [v0.2.0](https://github.com/wowica/xander/releases/tag/v0.2.0) (2025-05-08)

### Added

- Support for TxSubmission mini-protocol.
- Integration tests on CI using Yaci DevKit.

## [v0.1.1](https://github.com/wowica/xander/releases/tag/v0.1.1) (2025-02-19)

### Fixed

- Issue where the ledger state tracked by the Query OTP process wouldn't be
updated after establishing a connection. The result was that queries would
always return the same value.

## [v0.1.0](https://github.com/wowica/xander/releases/tag/v0.1.0) (2024-02-17)

### Added

- Establish connection to Cardano node via Unix socket file or Demeter.run URL
- Support for Ledger State Queries:
  * `:get_current_era`
  * `:get_current_block_height`
  * `:get_epoch_number`
  * `:get_current_tip`
