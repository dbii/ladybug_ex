defmodule LadybugEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :ladybug_ex,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      rustler_crates: [
        ladybug_nif: [
          path: "native/ladybug_nif",
          mode: rustc_mode(Mix.env())
        ]
      ],

      # Hex.pm package metadata
      description:
        "Elixir NIF bindings for LadybugDB - an embedded property graph database with Cypher query support",
      package: package(),

      # Documentation
      name: "LadybugEx",
      source_url: "https://github.com/tylerdavis/ladybug_ex",
      homepage_url: "https://github.com/tylerdavis/ladybug_ex",
      docs: [
        main: "LadybugEx",
        extras: ["README.md", "CHANGELOG.md"],
        groups_for_modules: [
          Core: [LadybugEx, LadybugEx.Database, LadybugEx.Connection],
          "Graph Operations": [LadybugEx.Graph],
          "Schema Management": [LadybugEx.Schema],
          Internal: [LadybugEx.Native]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.35.0", runtime: false},
      {:ex_doc, "~> 0.35.0", only: :dev, runtime: false}
    ]
  end

  defp rustc_mode(:prod), do: :release
  defp rustc_mode(_), do: :debug

  defp package do
    [
      name: "ladybug_ex",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/tylerdavis/ladybug_ex",
        "LadybugDB" => "https://github.com/lbugdb/lbug",
        "LadybugDB Website" => "https://www.ladybugdb.com"
      },
      files: ~w(
        lib
        native/ladybug_nif/src
        native/ladybug_nif/Cargo.toml
        native/ladybug_nif/Cargo.lock
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE
        .formatter.exs
      ),
      maintainers: ["Tyler Davis"]
    ]
  end
end
