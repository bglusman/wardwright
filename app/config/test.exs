import Config

config :tzdata, :autoupdate, :disabled

config :wardwright,
  serve_http: false,
  allow_mock_stream_chunks: true,
  allow_test_config: true,
  receipt_store_dir: nil,
  sqlite_store_path: nil
