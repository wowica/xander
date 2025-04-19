Application.stop(:xander)

# Configure ExUnit to exclude integration tests by default
ExUnit.configure(exclude: [:integration])

ExUnit.start()
