Logger.configure(level: :error)

# Configure ExUnit to exclude integration tests by default
ExUnit.configure(exclude: [:integration])

ExUnit.start()
