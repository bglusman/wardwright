ExUnit.start()
ExUnit.configure(exclude: [live_provider: true, counterfactual_replay_acceptance: true])
Code.require_file("../test_support/router_case.ex", __DIR__)
Code.require_file("../test_support/framework_adapter_smoke_case.ex", __DIR__)
