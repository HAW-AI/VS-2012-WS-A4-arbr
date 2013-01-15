-module(sender).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").

-define(SLOTS_PER_FRAME, 20).
-define(SLOT_LENGTH, 1000/?SLOTS_PER_FRAME).

%%
%% Include files
%%
-import(util, [timestamp/0, time_till_slot/1]).
%%
%% Exported Functions
%%
%% gen_fsm requires explicit export of his required functions
-export([init/1, handle_sync_event/4, handle_info/3, code_change/4, terminate/3, handle_event/3, deliver/2]).
-compile([export_all]).
-behaviour(gen_fsm).
-record( state, { coordinator, socket, datasource, address, port, message, slot=0, next_slot=0 }).
%%
%% API Functions
%%
start( Coordinator, Socket, Address, Port )->
  log("Starter: gestartet"),
  gen_fsm:start( ?MODULE, [ Coordinator, Socket, Address, Port ], [] ).

init([ Coordinator, Socket, Address, Port ]) ->
  log("Sender: init"),
  { ok, Datasource } = datasource:start(),
  { ok, slot_received, #state{ coordinator=Coordinator, socket=Socket, datasource=Datasource, address=Address, port=Port }}.

% fetch message from datasource
slot_received({ slot, Slot }, State) ->
  log("Slot received"),
  gen_server:cast( State#state.datasource, { get_next_value, self() }),
  log("Nach get_next_value"),
  { next_state, message_received, State#state{ slot=Slot } };
slot_received(Unknown, State) ->
  log("[UNKNOWN] slot_received received message [~p]",[Unknown]),
  { next_state, slot_received, State}.

message_received({ message, Message }, State) ->
  log("message received"),
  % fetch next slot from coordinator
  gen_server:cast(State#state.coordinator, { nextSlot, self() }),
  log("received Message [~p]", [Message]),
  { next_state, next_slot_received, State#state{ message=Message} };
message_received(Unknown, State) ->
  log("[UNKNOWN] message_received received message [~p]",[Unknown]),
  { next_state, message_received, State}.

next_slot_received({ nextSlot, Slot }, State) ->
  log("next slot received"),
  % if slot not passed
  % deliver message, and wait for next frame
  % else ?
  TimeLeft = time_till_slot(State#state.slot),
  case TimeLeft > 0 of
    true ->
%      timer:sleep(TimeLeft),
      gen_fsm:send_event_after(TimeLeft, deliver),
      { next_state, deliver, State#state{next_slot=Slot} };
    false ->
      log("TimeLeft<=0"),
      { next_state, slot_received, State }
  end;
next_slot_received(Unknown, State) ->
  log("[UNKNOWN] next_slot_received received message [~p]",[Unknown]),
  { next_state, next_slot_received, State}.

deliver(deliver, State) ->
      Socket = State#state.socket,
      Address = State#state.address,
      Port = State#state.port,
      Message = State#state.message,
      Packet = build_packet(Message, State#state.next_slot),
      gen_udp:send(Socket, Address, Port, Packet),
      log("Nachricht gesendet"),
      { next_state, slot_received, State }.

handle_event(stop, _StateName, State) ->
  utility:log("Sender wird ausgeschaltet"),
  {stop, normal, State}.

terminate( _StateName, _StateData, State) ->
	log("TERMINATING!"),
	gen_server:cast(State#state.datasource, stop),
	gen_udp:close(State#state.socket),
	ok.

%%
%% non API Functions
%%

% Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
build_packet( Message, Slot ) ->
  log("build packet"),
  Timestamp = timestamp(),
  log("Timestamp [~p]", [Timestamp]),
  log("Message [~p]", [Message]),
  Data = list_to_binary(Message),
  % Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
  Packet = << Data:24/binary,Slot:8/integer-big,Timestamp:64/integer-big>>,
  log("Packet [~p]",[Packet]),
  Packet.

log(Message) ->
	util:log( "Sender.log", Message ).
log(Message, Data) ->
	util:log( "Sender.log", Message, Data ).

%% gen_fsm API requirements
state_name( _Event, _From, State ) ->
  {reply, ok, state_name, State}.

handle_sync_event( _Event, _From, StateName, State ) ->
  {reply, ok, StateName, State}.

handle_info( Info, StateName, State ) ->
  log("Info: [~p]",[Info]),
  {noreply, StateName, State}.

code_change( _OldVsn, StateName, State, _Extra ) ->
  {ok, StateName, State}.
