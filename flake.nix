{
  description = "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)";

  # Re-hosted on the pure-gen stack. `gen-merge.lib` is the constructed merge engine (carries
  # gen-types); `gen-schema.lib` is the re-hosted (pure) registry. The library (./lib) is
  # nixpkgs-lib-free (ci/tests/purity.nix); nixpkgs is pulled ONLY in ci/ (the harness).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-merge.url = "github:sini/gen-merge";
    gen-schema.url = "github:sini/gen-schema";
  };

  outputs =
    {
      gen-prelude,
      gen-merge,
      gen-schema,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        merge = gen-merge.lib;
        schema = gen-schema.lib;
      };
    };
}
