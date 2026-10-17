-module(m5_power).
-export([deep_sleep/0, deep_sleep/1, deep_sleep/2, timer_sleep/1, set_battery_charge/1, set_charge_current/1, set_charge_voltage/1, get_battery_level/0, is_charging/0, get_type/0]).

get_battery_level() -> m5_emu_input:battery().
is_charging() -> false.
get_type() -> unknown.
deep_sleep() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
deep_sleep(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
deep_sleep(_, _) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
timer_sleep(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
set_battery_charge(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
set_charge_current(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
set_charge_voltage(_) -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
