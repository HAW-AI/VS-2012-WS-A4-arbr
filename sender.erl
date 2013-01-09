-module(sender).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

% tasks
% - waiting for slot
% - waiting for message
% - deliver message
-behaviour(gen_fsm).
%%
%% Include files
%%
-import(util, [log/2]).
%%
%% Exported Functions
%%
%% gen_fsm erwartet bestimmte exports, export_all reicht nicht aus
-export([]).

-record(state,{coordinatorPID,socket,datasourcePID}).
%%
%% API Functions
%%
start(CoordinatorPID,Socket)->
	gen_fsm:start(?MODULE,[CoordinatorPID,Socket],[]).

init([CoordinatorPID,Socket]) ->
	{ok, DatasourcePID} = datasource:start(),
	{ok,get_data,#state{coordinatorPID = CoordinatorPID,
							 socket=Socket,
							 datasourcePID=DatasourcePID}}.

terminate(StateName,StateData,State) ->
	gen_server:cast(State#state.datasourcePID, stop),
	gen_udp:close(State#state.socket),
	ok.

get_data({slot,Slot},State) ->
	gen_server:cast(State#state.datasourcePID, {get_data,self()}).
	
	


%%
%% Local Functions
%%
log(Message) ->
	util:log("Datasource.log",Message).