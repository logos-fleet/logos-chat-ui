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
    # TEST-ONLY, and followed rather than pinned. The module never builds
    # against the design system -- `import Logos.Theme` / `Logos.Controls` are
    # resolved by whichever host mounts this view -- but the QML check below
    # has to resolve them itself, and it needs the design system's SOURCE tree:
    # every built logos-design-system store path holds a STATIC QML module with
    # no on-disk qmldir, so `-import <store>/lib` fails with
    # `module "Logos.Theme" is not installed`.
    logos-design-system.follows = "logos-module-builder/logos-design-system";
  };

  outputs = inputs@{ logos-module-builder, logos-delivery-module, logos-design-system, ... }:
    let
      base = logos-module-builder.lib.mkLogosQmlModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = { delivery_module = logos-delivery-module; } // inputs;
      };

      nixpkgs = logos-module-builder.inputs.nixpkgs;
      pkgsFor = system: import nixpkgs { inherit system; };

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

      # THE ONLY THING IN THIS REPO THAT READS ITS QML (logos-workspace#248).
      #
      # mkLogosQmlModule copies src/qml into the artifact as PLAIN SOURCE -- no
      # qmlcachegen, no .qmlc -- so `nix build` is green with a QML error in
      # the view, and the first thing that ever compiles ChatView.qml is the
      # host that mounts it on a device. #248 is what that costs: a binding
      # against a property StatusBar no longer had shipped, and the app said
      # `Cannot assign to non-existent property "failures"` when a user opened
      # Chat.
      #
      # qmltestrunner over tests/qml is the whole check: tst_components.qml's
      # per-component cases and tst_chatview.qml's construction of the entry
      # view. It runs from a WRITABLE COPY of the repo because the tests
      # resolve the view relative to themselves.
      #
      # Three import paths besides Qt's own, and a reason for each:
      #   src/qml            `import ChatUi` -- the module's own components
      #   tests/qml-stubs    `import Logos.ChatBackend`, which is host-registered
      #                      C++ at runtime and has no QML to resolve to here
      #   design system      Logos.Theme / Logos.Controls / Logos.Icons, from
      #                      SOURCE (see the input comment above)
      qmlCheck = system:
        let
          pkgs = pkgsFor system;
          qtDeclarative = pkgs.qt6.qtdeclarative;
        in pkgs.runCommand "logos-chat-ui-qml-tests" { } ''
          cp -R ${./.} repo
          chmod -R u+w repo
          cd repo

          export HOME="$TMPDIR"
          export XDG_RUNTIME_DIR="$TMPDIR"
          export QT_QPA_PLATFORM=offscreen
          # Deterministic across platforms: the native macOS style refuses the
          # design system's control customisation and would change what the
          # cases see.
          export QT_QUICK_CONTROLS_STYLE=Basic

          # Redirected, never piped: a pipe would hand nix the exit status of
          # `tee` and a failing suite would pass.
          if ! ${qtDeclarative}/bin/qmltestrunner \
                 -input tests/qml \
                 -import src/qml \
                 -import tests/qml-stubs \
                 -import ${logos-design-system}/src/qml \
                 -import ${qtDeclarative}/lib/qt-6/qml \
                 -platform offscreen > qml-tests.log 2>&1; then
            cat qml-tests.log
            echo "chat_ui: the QML suite failed -- see the FAIL! lines above" >&2
            exit 1
          fi
          cat qml-tests.log
          cp qml-tests.log "$out"
        '';

      # `nix run .#exchange`: drive the real two-party message round-trip and hold
      # the receiving window open showing the result. The doc-test launches this
      # to capture one post-exchange screenshot (see doctests/chat-ui-exchange.test.yaml);
      # the full flow lives in docs/two-instance-exchange.md. APP_BIN is this
      # flake's standalone runner; the driver scripts are bundled from
      # ./doctests/exchange.
      exchangeRunner = system:
        let pkgs = pkgsFor system;
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
          pkgs = pkgsFor system;
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
        # Over `configFor`'s keys MINUS the Windows pseudo-system, which is
        # the four native systems -- the only ones a qmltestrunner runs on.
        # Neither of the other two sets would do: `configFor` itself carries
        # x86_64-windows, where `pkgsFor` does not even evaluate (see the
        # `windowsSystem` comment above), and `packages` carries the mobile
        # pseudo-systems on top of that.
        checks = nixpkgs.lib.genAttrs
          (builtins.filter (system: system != windowsSystem)
            (builtins.attrNames base.configFor))
          (system: (base.checks.${system} or { }) // { qml = qmlCheck system; });
      };
}
