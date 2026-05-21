{
  description = "gen-aspects: aspect-oriented composition types for Nix module systems";

  inputs.den-schema.url = "github:sini/den-schema";

  outputs = _: {
    __functor = _: import ./.;
  };
}
