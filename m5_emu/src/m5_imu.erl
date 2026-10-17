-module(m5_imu).
-export([is_enabled/0, get_type/0, get_accel/0, get_gyro/0, get_mag/0]).

is_enabled() -> false.
get_type() -> unknown.
get_accel() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_gyro() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_mag() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
