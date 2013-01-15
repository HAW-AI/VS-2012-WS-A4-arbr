-module(util).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).
-import(werkzeug, [logging/2]).
-define(SLOTS_PER_FRAME, 20).
-define(SLOT_LENGTH, 1000/?SLOTS_PER_FRAME).


log(File, Message) -> log(File, Message, []).
log(File, Message, Data) ->
  logging(File, io_lib:format("[~s] (~p) "++Message++"~n",[timestamp_log(),self()]++Data)).

timestamp_log() ->
  {Year, Month, Day} = date(),
  {Hour, Minute, Second} = time(),
  lists:flatten(
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",[Year, Month, Day, Hour, Minute, Second])
  )++","++millisec().

millisec() ->
  {_, _, MicroSec} = now(),
  string:substr( float_to_list(MicroSec/ 1000000), 3, 3).

timestamp() ->
  {MegaSecs, Secs, MicroSecs} = now(), % would erlang:timestamp() also work? i'm unsure
  trunc((MegaSecs * math:pow(10,9)) + (Secs * math:pow(10,3)) + (MicroSecs div 1000)).

time_till_slot(Slot) ->
  (Slot * 50) - time_in_frame().

slot_from(Timestamp) ->
  trunc((Timestamp rem 1000) / ?SLOT_LENGTH).

time_in_frame() ->
  { _, _, MicroSecs } = now(),
  MicroSecs div 1000.
