# Used by "mix format"
[
  plugins: [Quokka],
  quokka: [
    autosort: [:map, :defstruct, :schema],
    only: [
      :autosort,
      :blocks,
      :configs,
      :defs,
      :deprecations,
      :module_directives,
      :pipes,
      :single_node,
      :tests
    ]
  ],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
