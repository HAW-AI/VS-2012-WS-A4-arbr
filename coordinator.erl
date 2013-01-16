-module(coordinator).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

-behaviour(gen_server).
% tasks
% - start datasource
% - start receiver
% - start sender
% - manage slots

-export([init/1, handle_cast/2, handle_info/2, code_change/3, terminate/2, handle_call/3]).

-define(SENDPORT,14010).

-record(state, {receiverPID, senderPID, sendport, recport, wished_slots=dict:new(), used_slots=dict:new(), next_slot, station }).

start([RecPort,Station,MulticastIP,LocalIP])->
	%log("Coordinator gestartet"),
	gen_server:start(?MODULE,[RecPort,?SENDPORT,Station,MulticastIP,LocalIP],[]).

init([StringRecPort,SendPort,Station,StringMulticastIP,StringLocalIP])->
	%log("Coordinator init [~p]",[Station]),
	%http://erldocs.com/R15B/kernel/gen_udp.html
	%http://erldocs.com/R15B/kernel/inet.html#setopts/2
	%http://stackoverflow.com/questions/78826/erlang-multicast

	RecPort = list_to_integer(atom_to_list(StringRecPort)),
	{ ok, MulticastIP } = inet_parse:address(atom_to_list(StringMulticastIP)),
	{ ok, LocalIP } = inet_parse:address(atom_to_list(StringLocalIP)),
	%log("[~p]Coordinator IPs angepasst",[Station]),
	%log("[~p]RecPort: ~p",[Station,RecPort]),
	%log("[~p]MulticastIP: ~p",[Station,MulticastIP]),
	%log("[~p]LocalIP: ~p",[Station,LocalIP]),
	{ok,RecSocket} = gen_udp:open(RecPort,[
										   binary,
										   inet,
										   {active, true},
										   {reuseaddr, true},
										   {multicast_loop, true},
										   {add_membership,{MulticastIP,LocalIP}},
										   {multicast_if, LocalIP}]
								 ),
	%log("[~p]Coordinator RecSocket geöffnet",[Station]),
	{ok,SendSocket} = gen_udp:open(SendPort,[
											 binary,
											 inet,
											 {active, true},
											 {reuseaddr, true},
											 {multicast_loop, true},
											 {multicast_if, LocalIP},
											 {ip,LocalIP}]
								  ),
	%log("[~p]Coordinator Sockets geöffnet",[Station]),

	{ok,ReceiverPID} = receiver:start(self(),RecSocket,Station),
	%log("[~p]Coordinator: Receiver gestartet",[Station]),
	{ok,SenderPID} = sender:start(self(),SendSocket,MulticastIP,RecPort,Station),

	gen_udp:controlling_process(RecSocket, ReceiverPID),
	gen_udp:controlling_process(SendSocket, SenderPID),

	%log("[~p]Coordinator - alle Sockets geöffnet, und sender/receiver gestartet",[Station]),
	next_frame_timer(Station),
	random:seed(now()),
	NextSlot = random:uniform(20) -1,

	{ok, #state{
				receiverPID=ReceiverPID,
				senderPID=SenderPID,
				sendport=SendPort,
				recport=RecPort,
				next_slot=NextSlot,
				station=Station
				}}.

next_frame_timer(_Station) ->
	%log("[~p]Next frame timer",[Station]),
	%log("[~p]Timestamp: [~p]",[Station,util:timestamp()]),
	%log("[~p]Millisec: [~p]",[Station,(util:timestamp() rem 1000)]),
	%log("[~p]Timediff: [~p]",[Station,1000 - (util:timestamp() rem 1000)]),
	erlang:send_after(1000 - (util:timestamp() rem 1000), self(), frame_start).

handle_cast(frame_start, State) ->
	%log("[~p]=========================Coordinator: start frame==================================",[State#state.station]),
	% send all non collided messages to sink (ugly hack!)
	CollisionFreeMessages = dict:filter(fun(_Key, Value) -> length(Value) == 1 end, State#state.used_slots),
	dict:fold(fun(_Key, Value, _Accu) -> gen_server:cast(self(),{ datasink, Value }) end, ok, CollisionFreeMessages),
	% did we collide in previous frame?
	Collided = lists:length(dict:fetch(State#state.next_slot, State#state.used_slots)) > 1,
	% send wished or free slot to sender
	Slot = calculate_next_slot(State),
	%log("[~p]Sending nextslot",[State#state.station]),
	gen_fsm:send_event(State#state.senderPID, { slot, Slot }),
	next_frame_timer(State#state.station),
	{noreply, State#state{ used_slots=dict:new(), wished_slots=dict:new()}};

handle_cast({datasink, Data},State)->
	%log("[~p]Neue Nachricht empfangen: ~p",[State#state.station,Data]),
	{noreply, State};

handle_cast({recieved, _RecievedTimestamp, Packet}, State)->
	%log("[~p]Coordinator recieved",[State#state.station]),
	{ Station, StationNumber, Data, SlotWish, Timestamp} = parse_packet(Packet),
	Slot = util:slot_from(Timestamp), % or from RecievedTimestamp?


	WishedSlots = case slot_collision(Slot, State#state.used_slots) of
		true ->
			dict:erase(SlotWish, State#state.wished_slots),
			ok;
		false ->
			dict:append(SlotWish, StationNumber, State#state.wished_slots),
	end,
	UsedSlots = dict:append(Slot, { Station, StationNumber, Data }, State#state.used_slots),
	{noreply, State#state{ used_slots=UsedSlots, wished_slots=WishedSlots }};
handle_cast(Any, State)->
	%log("Unknown message received: [~p]",[Any]),
	{noreply,State}.

calculate_next_slot(State) ->
	case slot_wished_by_more_than_two(State#state.next_slot, State#state.wished_slots) of
		% collision in wishlist, find alternative.
		true ->
			WishedSlots = slots_with_only_one_wish(State#state.wished_slots),
			FreeSlots = lists:subtract(lists:seq(0,19), WishedSlots),
			if
				length(FreeSlots) == 0 ->
					0; % ugly fallback, no free slot found!
				true ->
					FreeSlotsLength = length(FreeSlots),
					RandomElementIndex = random:uniform(FreeSlotsLength),
					lists:nth(RandomElementIndex,FreeSlots)
			end;
		false ->
			% "our" slot is still ours
			State#state.next_slot
	end.

slots_with_only_one_wish(Slots) ->
	dict:fetch_keys(dict:filter(fun(_Key, Value) -> length(Value) == 1 end, Slots)).

slot_wished_by_more_than_two(Slot, Slots) ->
  case dict:is_key(Slot, Slots) of
  	true -> length(dict:fetch(Slot, Slots)) > 1;
  	false -> false
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
	%log("TERMINATING!"),
	gen_server:cast(State#state.receiverPID,{stop}),
	gen_fsm:cast(State#state.senderPID,{stop}),
	ok.

log(Message) ->
	util:log("Coordinator.log",Message).
log(Message, Data) ->
	util:log("Coordinator.log",Message, Data).

%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(frame_start, State) ->
  %log("[~p]Got frame_start",[State#state.station]),
  gen_server:cast(self(), frame_start),
  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
