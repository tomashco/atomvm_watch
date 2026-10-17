-module(m5_in_i2c).
-export([set_port/3, begin_/3]).

set_port(_, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
begin_(_, _, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
