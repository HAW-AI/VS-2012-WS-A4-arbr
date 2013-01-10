-module(coordinator).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

-behaviour(gen_server).
-import(util, [log/2]).
% tasks
% - start datasource
% - start receiver
% - start sender
% - manage slots

-export([init/1, handle_cast/2, handle_info/2, code_change/3, terminate/2, handle_call/3]).

-define(SENDPORT,14010).

-record(state, {receiverPID, senderPID, sendport, recport, wished_slots=dict:new(), used_slots=dict:new(), next_slot }).

start(RecPort,Station,MulticastIP,LocalIP)->
	gen_server:start(?MODULE,[RecPort,?SENDPORT,Station,MulticastIP,LocalIP],[]).

init([RecPort,SendPort,_Station,MulticastIP,LocalIP])->
	%http://erldocs.com/R15B/kernel/gen_udp.html
	%http://erldocs.com/R15B/kernel/inet.html#setopts/2
	%http://stackoverflow.com/questions/78826/erlang-multicast
	{ok,RecSocket} = gen_udp:open(RecPort,[
										   binary,inet,
										   {multicast_loop, true},
										   {add_membership,{MulticastIP,LocalIP}},
										   {multicast_if, LocalIP}]
								 ),
	{ok,SendSocket} = gen_udp:open(SendPort,[
											 binary,
											 inet,
											 {multicast_loop, true},
											 {multicast_if, LocalIP},
											 {ip,LocalIP}]
								  ),

	{ok,ReceiverPID} = receiver:start(self(),RecSocket),
	{ok,SenderPID} = sender:start(self(),SendSocket,MulticastIP,RecPort),

	next_frame_timer(),
	[ NextSlot | _ ] = werkzeug:shuffle(lists:seq(0,19)),

	{ok, #state{
				receiverPID=ReceiverPID,
				senderPID=SenderPID,
				sendport=SendPort,
				recport=RecPort,
				next_slot=NextSlot
				}}.

next_frame_timer() ->
	erlang:send_after(1000 - (util:timestamp() rem 1000), self(), frame_start).

handle_cast(frame_start, State) ->
	% send all non collided messages to sink (ugly hack!)
	CollisionFreeMessages = dict:filter(fun(_Key, Value) -> lists:length(Value) == 1 end, State#state.used_slots),
	dict:fold(fun(_Key, Value, _Accu) -> gen_server:cast(self(),{ datasink, Value }) end, ok, CollisionFreeMessages),
	% send wished or free slot to sender
	NextSlot = calculate_next_slot(State),
	gen_server:cast(State#state.senderPID, { nextSlot, NextSlot }),
	next_frame_timer(),
	{noreply, State#state{ used_slots=dict:new(), wished_slots=dict:new() }};

handle_cast({datasink, Data},State)->
	log("Neue Nachricht empfangen: ~p",[Data]),
	{noreply, State};

handle_cast({nextSlot, SenderPID}, State)->
	log("Der Sender hat nach dem nächsten Slot gefragt"),
	NextSlot = calculate_next_slot(State),
	gen_server:cast(SenderPID, { nextSlot, NextSlot }),
	{noreply, State#state{ next_slot=NextSlot }};

handle_cast({recieved, _RecievedTimestamp, Packet}, State)->
	{ Station, StationNumber, Data, SlotWish, Timestamp} = parse_packet(Packet),
	Slot = util:slot_from(Timestamp), % or from RecievedTimestamp?

	case slot_collision(Slot, State#state.used_slots) of
		true ->
			log("Collision!") % by dict:fetch(Slot, State#state.used_slots)
	end,
	UsedSlots = dict:append(Slot, lists:faltten([ Station, StationNumber, Data ]), State#state.used_slots),
	WishedSlots = dict:append(SlotWish, StationNumber, State#state.wished_slots),
	{noreply, State#state{ used_slots=UsedSlots, wished_slots=WishedSlots }}.

calculate_next_slot(State) ->
	Count = lists:size(dict:fetch(State#state.next_slot, State#state.wished_slots)),
	if
		Count < 2 ->
			State#state.next_slot;
		true ->
			[ Slot | _ ] = werkzeug:shuffle(lists:substract(lists:seq(0,19), dict:fetch_keys(State#state.used_slots))),
			Slot
	end.

slot_collision(Slot, UsedSlots) ->
	dict:is_key(Slot, UsedSlots).

parse_packet(Packet) ->
	<<Station:8/binary,
    StationNumber:2/binary,
    Data:14/binary,
    Slot:8/integer-big,
    Timestamp:64/integer-big
  >> = Packet,
  {Station, StationNumber, Data, Slot, Timestamp }.

terminate(normal,State)->
	gen_server:cast(State#state.receiverPID,{stop}),
	gen_fsm:cast(State#state.senderPID,{stop}),
	ok.

log(Message) ->
	util:log("Coordinator.log",Message).

%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
