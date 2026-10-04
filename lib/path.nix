# THE ONE RENDERING of a structured path: a list of segments to a "/"-joined string.
#
# A path is a structured value (identity design §1: nesting is a parent edge, and the slash-joined
# path is only its rendering, ADR-0012). A rendering that names a node must be injective, so a segment
# holding the separator is escaped rather than joined raw: `[ "f/x" ]` renders `f%2Fx`, `[ "f" "x" ]`
# renders `f/x`, and the two never collide. `%` is escaped first so the escape itself cannot be forged.
# A segment holding neither renders byte-identically to the raw join, so every ordinary key is unmoved.
# `parse` is the inverse over a rendered string. Dep-free (builtins only) → a bare value.
let
  escape = builtins.replaceStrings [ "%" "/" ] [ "%25" "%2F" ];
  unescape = builtins.replaceStrings [ "%2F" "%25" ] [ "/" "%" ];
in
{
  inherit escape unescape;
  render = path: builtins.concatStringsSep "/" (map escape path);
  parse =
    s: map unescape (builtins.filter (seg: builtins.isString seg && seg != "") (builtins.split "/" s));
}
