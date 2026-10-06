# OTP's inets is not on the code path unless a dependency lists it; the tests use :httpc.
for dir <- Path.wildcard(Path.join([to_string(:code.root_dir()), "lib", "inets-*", "ebin"])),
    do: Code.prepend_path(dir)

{:ok, _} = Application.ensure_all_started(:inets)
ExUnit.start()
