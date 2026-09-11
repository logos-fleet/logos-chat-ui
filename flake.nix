{
  description = "Logos Chat UI - QML view + C++ backend module";

  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    # Follow chat_module's own builder, so the logos-protocol/logos-qt-sdk
    # chain matches across both.
    logos-module-builder.follows = "chat_module/logos-module-builder";
    # Pinned to the chat_module commit that moved onto a logos-module-builder
    # carrying the typed-record codegen this view now consumes. A rev rather
    # than a tag, and the logos-fleet fork rather than logos-co, only because no
    # release carries either yet -- re-pin to the tag once one is cut, and keep
    # the lockstep the paragraph above describes.
    chat_module.url = "github:logos-fleet/logos-chat-module/a55cbf180884f9d75aa279e79b85b9a285e17aa1";
    # Follow chat_module's delivery pin, so both build against the same
    # delivery module.
    logos-delivery-module.follows = "chat_module/logos-delivery-module";
  };

  outputs = inputs@{ logos-module-builder, logos-delivery-module, ... }:
    let
      base = logos-module-builder.lib.mkLogosQmlModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = { delivery_module = logos-delivery-module; } // inputs;
      };

      nixpkgs = logos-module-builder.inputs.nixpkgs;

      # x86_64-windows is a cross PSEUDO-SYSTEM: only `packages` means anything
      # under it, and neither a standalone runner nor a doc-test does. Both also
      # fail to evaluate there -- mkLogosQmlModule's own `apps.<system>.default`
      # resolves the runner against a NATIVE Windows nixpkgs ("Package … is not
      # available on the requested hostPlatform"), and the two doc-test runners
      # die one layer earlier in `import nixpkgs { inherit system; }` ("called
      # without required argument 'runtimeShell'"). So `apps` drops the key
      # whole, and `packages` gains `exchange` only where it evaluates;
      # `packages.x86_64-windows.*` is untouched and is what Windows consumes.
      windowsSystem = "x86_64-windows";

      # `nix run .#exchange`: drive the real two-party message round-trip and hold
      # the receiving window open showing the result. The doc-test launches this
      # to capture one post-exchange screenshot (see doctests/chat-ui-exchange.test.yaml);
      # the full flow lives in docs/two-instance-exchange.md. APP_BIN is this
      # flake's standalone runner; the driver scripts are bundled from
      # ./doctests/exchange.
      exchangeRunner = system:
        let pkgs = import nixpkgs { inherit system; };
        in pkgs.writeShellApplication {
          name = "chat-ui-exchange";
          runtimeInputs = with pkgs; [ nodejs coreutils util-linux procps bash ];
          text = ''
            export APP_BIN="${base.apps.${system}.default.program}"
            exec bash ${./doctests/exchange}/run-exchange-show.sh "$@"
          '';
        };

      # `nix run .#group`: form a real three-party group conversation and hold the
      # newest member's window open showing the result. The doc-test launches this
      # to capture one screenshot of the formed group (see
      # doctests/chat-ui-group.test.yaml). APP_BIN is this flake's standalone
      # runner; the driver scripts are bundled from ./doctests/group.
      groupApp = system:
        let
          pkgs = import nixpkgs { inherit system; };
          runner = pkgs.writeShellApplication {
            name = "chat-ui-group";
            runtimeInputs = with pkgs; [ nodejs coreutils util-linux procps bash ];
            text = ''
              export APP_BIN="${base.apps.${system}.default.program}"
              exec bash ${./doctests/group}/run-group-show.sh "$@"
            '';
          };
        in {
          type = "app";
          program = "${runner}/bin/chat-ui-group";
        };
    in
      base // {
        apps = builtins.mapAttrs
          (system: sysApps: sysApps // {
            exchange = { type = "app"; program = "${exchangeRunner system}/bin/chat-ui-exchange"; };
            group = groupApp system;
          })
          (builtins.removeAttrs base.apps [ windowsSystem ]);
        # Also a package so `nix build .#exchange` resolves: the doc-test runner
        # pre-builds its launch target that way to warm the store before the run.
        packages = builtins.mapAttrs
          (system: sysPkgs: sysPkgs // nixpkgs.lib.optionalAttrs
            (system != windowsSystem) { exchange = exchangeRunner system; })
          base.packages;
      };
}
