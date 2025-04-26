{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_12_9, cargo, rust-bin }:

let
    rustVersion = "1.81.0";
    cargo = rust-bin.stable.${rustVersion}.default;
in
buildPgrxExtension_0_12_9 rec {
  pname = "pg_graphql";
  version = "1.5.11";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "powerbase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-BMZc9ui+2J3U24HzZZVCU5+KWhz+5qeUsRGeptiqbek=";
  };

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  
  CARGO = "${cargo}/bin/cargo";
  
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  # Setting RUSTFLAGS in env to ensure it's available for all phases
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    PGPORT = if (lib.versions.major postgresql.version) == "17" then "5440" else "5439";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    NIX_BUILD_CORES = "4";  # Limit parallel jobs
    CARGO_BUILD_JOBS = "4"; # Limit cargo parallelism
  };
  CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG = true;


  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/skorpland/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
