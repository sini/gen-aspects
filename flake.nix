{
  description = "gen-aspects: aspect-oriented composition types for Nix module systems";
  outputs = _: {
    __functor = _: import ./.;
  };
}
