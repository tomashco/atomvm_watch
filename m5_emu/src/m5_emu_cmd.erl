-module(m5_emu_cmd).
-export([encode/1, exec_script/1, to_rgb888/1]).

exec_script(Cmds) -> [<<"m5emu.exec(">>, encode(Cmds), <<")">>].

encode(Cmds) -> [$[, join([encode_cmd(C) || C <- Cmds]), $]].

encode_cmd(Cmd) when is_tuple(Cmd) ->
    [Name | Args] = tuple_to_list(Cmd),
    [$[, join([str(atom_to_binary(Name, utf8)) | [val(A) || A <- Args]]), $]].

val(I) when is_integer(I) -> integer_to_binary(I);
val(F) when is_float(F) -> float_to_binary(F, [{decimals, 4}, compact]);
val(A) when is_atom(A) -> str(atom_to_binary(A, utf8));
val(B) when is_binary(B) -> str(B);
val(L) when is_list(L) -> str(iolist_to_binary(L)).

str(Bin) -> [$", escape(Bin), $"].
escape(<<>>) -> [];
escape(<<$", R/binary>>) -> [<<"\\\"">> | escape(R)];
escape(<<$\\, R/binary>>) -> [<<"\\\\">> | escape(R)];
escape(<<$\n, R/binary>>) -> [<<"\\n">> | escape(R)];
escape(<<$\r, R/binary>>) -> [<<"\\r">> | escape(R)];
escape(<<$\t, R/binary>>) -> [<<"\\t">> | escape(R)];
escape(<<C, R/binary>>) when C < 16#20 -> [io_lib:format("\\u~4.16.0b", [C]) | escape(R)];
escape(<<C, R/binary>>) -> [C | escape(R)].

join([]) -> [];
join([X]) -> [X];
join([X | Rest]) -> [X, $, | join(Rest)].

to_rgb888(I) when is_integer(I) -> I band 16#FFFFFF;
to_rgb888({rgb888, I}) -> I band 16#FFFFFF;
to_rgb888({rgb, {R, G, B}}) -> (R bsl 16) bor (G bsl 8) bor B;
to_rgb888({rgb565, C}) ->
    R5 = (C bsr 11) band 16#1F, G6 = (C bsr 5) band 16#3F, B5 = C band 16#1F,
    R = (R5 bsl 3) bor (R5 bsr 2), G = (G6 bsl 2) bor (G6 bsr 4), B = (B5 bsl 3) bor (B5 bsr 2),
    (R bsl 16) bor (G bsl 8) bor B.
