-module(m5_power_axp192).
-export([get_battery_level/0, get_battery_voltage/0, get_battery_discharge_current/0, get_battery_charge_current/0, get_battery_power/0, get_acin_voltage/0, get_acin_current/0, get_vbus_voltage/0, get_vbus_current/0, get_aps_voltage/0, get_internal_temperature/0]).

get_battery_level() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_battery_voltage() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_battery_discharge_current() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_battery_charge_current() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_battery_power() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_acin_voltage() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_acin_current() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_vbus_voltage() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_vbus_current() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_aps_voltage() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
get_internal_temperature() -> m5_emu_unsupported:call(?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY).
