{
  description = "Write composeable HTML with Nix!";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;

    first     = n: lib.substring 0 n;
    dropFirst = n: string: lib.substring n (lib.stringLength string - n) string;

    last     = n: string: lib.substring (lib.stringLength string - n) n string;
    dropLast = n: string: lib.substring 0 (lib.stringLength string - n) string;

    escape = lib.strings.escapeXML;

    attrsetToHtmlAttrs = attrs:
      lib.concatStringsSep " "
        (lib.mapAttrsToList (k: v: ''${k}="${escape (toString v)}"'') attrs);

    dottedNameToTag = name:
      if first 1 name == "."
      then "</${dropFirst 1 name}>"

      else if last 1 name == "."
      then "<${dropLast 1 name}>"

      else "<${name}>";

    # When doing <name>, these won't return HTML tags.
    propagatedFindFiles = [ "nixpkgs" ];
  in {
    raw = str: {
      _type  = "__trustedString";
      __toString = _: str;
    };

    call = scopedImport self;

    DOCTYPE = self.__findFile __nixPath "!DOCTYPE html";

    __findFile = nixPath: name: if builtins.elem name propagatedFindFiles then __findFile nixPath name else {
      outPath = dottedNameToTag name;

      __functor = this: next:
        # Is a list. Consume each item. Treat it as if it was passed in one by one.
        if lib.isList next
        then lib.foldl' (this: this) (this (lib.head next)) (lib.tail next)

        # We are passed in a functor/function that doesn't have an outPath meaning
        # it is not a HTML tag. This means the user forgot to call it.
        else if lib.isFunction next && !(next ? outPath)
        then throw ''
          You probably didn't mean to pass a function into the tag,
          and forgot some parenthesis to actually call the function.

          This is a common mistake, which usually looks like this:

            <p>raw "Foo Bar Baz"<.p>

          You probably meant to write something like this:

            <p>(raw "Foo Bar Baz")<.p>
        ''

        # Not an attrset, list or a function.
        # Just add it onto the HTML after stringifying it.
        else if !lib.isAttrs next
        then this // {
          outPath = (toString this) + escape (toString next);
        }

        else if (lib.isAttrs next) && (next._type or null =="__trustedString") then
        this // {
          outPath = (toString this) + (toString next); 
        }
        
        # An attrset. But not a tag. This means it must be HTML attributes.
        # We need to insert it right before the '>' or '/>' at the end of our string
        # and error if it doesn't end with a tag.
        #
        # Due to how it is implemented, passing multiple attrsets to a single
        # tag to combine them works. Here is an example:
        #
        #     <foo>{bar="baz";}{fizz="fuzz";}
        #
        # This will output the following HTML:
        #
        #     <foo bar="baz" fizz="fuzz">
        else if lib.isAttrs next && !(next ? outPath)
        then let
          lastElementIsTag         = last 1 (toString this) == ">";
          lastElementIsSelfClosing = last 2 (toString this) == "/>";
        in this // {
          outPath = let
            attrs = attrsetToHtmlAttrs next;
          in if !lastElementIsTag then
            throw "Attributes must come right after a tag: '${if attrs != "" then attrs else "<empty attrs>"}'"
          else
            (dropLast (if lastElementIsSelfClosing then 2 else 1) (toString this))
            + (if attrs != "" then " " else "") # Keep it pretty.
            + attrs
            + (if lastElementIsSelfClosing then "/>" else ">");
        }
        
        # The next element is a tag with the `outPath` attribute which means it's a
        # start, closing or self closing tag. Just append it onto our string.
        else this // {
          outPath = "${this}${next}";
        };
    };
  };
}
