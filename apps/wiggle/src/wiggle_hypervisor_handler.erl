-module(wiggle_hypervisor_handler).
-include("wiggle.hrl").

-export([allowed_methods/3,
         permission_required/1,
         get/1,
         read/2,
         write/3,
         delete/2]).

-ignore_xref([allowed_methods/3,
              get/1,
              permission_required/1,
              read/2,
              write/3,
              delete/2]).

allowed_methods(_Version, _Token, []) ->
    [<<"GET">>];

allowed_methods(_Version, _Token, [_Hypervisor]) ->
    [<<"GET">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"config">>|_]) ->
    [<<"PUT">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"characteristics">>|_]) ->
    [<<"PUT">>, <<"DELETE">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"metadata">>|_]) ->
    [<<"PUT">>, <<"DELETE">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"services">>]) ->
    [<<"PUT">>, <<"GET">>].

get(State = #state{path = [Hypervisor | _]}) ->
    Start = now(),
    R = libsniffle:hypervisor_get(Hypervisor),
    ?MSniffle(?P(State), Start),
    R.

permission_required(#state{path = []}) ->
    {ok, [<<"cloud">>, <<"hypervisors">>, <<"list">>]};

permission_required(#state{method = <<"GET">>, path = [Hypervisor]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"get">>]};

permission_required(#state{method = <<"PUT">>, path = [Hypervisor, <<"config">> | _]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(#state{method = <<"PUT">>, path = [Hypervisor, <<"metadata">> | _]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(#state{method = <<"DELETE">>, path = [Hypervisor, <<"metadata">> | _]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(#state{method = <<"PUT">>, path = [Hypervisor, <<"characteristics">> | _]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(#state{method = <<"DELETE">>, path = [Hypervisor, <<"characteristics">> | _]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(#state{method = <<"GET">>, path = [Hypervisor, <<"services">>]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"get">>]};

permission_required(#state{method = <<"PUT">>, path = [Hypervisor, <<"services">>]}) ->
    {ok, [<<"hypervisors">>, Hypervisor, <<"edit">>]};

permission_required(_State) ->
    undefined.

%%--------------------------------------------------------------------
%% GET
%%--------------------------------------------------------------------

read(Req, State = #state{token = Token, path = [], full_list=FullList, full_list_fields=Filter}) ->
    Start = now(),
    {ok, Permissions} = libsnarl:user_cache(Token),
    ?MSnarl(?P(State), Start),
    Start1 = now(),
    {ok, Res} = libsniffle:hypervisor_list([{must, 'allowed', [<<"hypervisors">>, {<<"res">>, <<"name">>}, <<"get">>], Permissions}], FullList),
    ?MSniffle(?P(State), Start1),
    Res1 = case {Filter, FullList} of
               {_, false} ->
                   [ID || {_, ID} <- Res];
               {[], _} ->
                   [ID || {_, ID} <- Res];
               _ ->
                   [jsxd:select(Filter, ID) || {_, ID} <- Res]
           end,
    {Res1, Req, State};

read(Req, State = #state{path = [_Hypervisor, <<"services">>], obj = Obj}) ->
    Snaps = jsxd:fold(fun(UUID, Snap, Acc) ->
                              [jsxd:set(<<"uuid">>, UUID, Snap) | Acc]
                      end, [], jsxd:get(<<"services">>, [], Obj)),
    {Snaps, Req, State};

read(Req, State = #state{path = [_Hypervisor, <<"services">>, Service],
                         obj = Obj = [{_,_}|_]}) when is_binary(Service) ->
    {jsxd:get([<<"services">>, Service], [{}], Obj), Req, State};

read(Req, State = #state{path = [_Hypervisor], obj = Obj}) ->
    {Obj, Req, State}.


%%--------------------------------------------------------------------
%% PUT
%%--------------------------------------------------------------------

write(Req, State = #state{path = [Hypervisor, <<"config">>]},
      [{<<"alias">>, V}]) when is_binary(V)->
    Start = now(),
    libsniffle:hypervisor_set(Hypervisor, [<<"alias">>], V),
    ?MSniffle(?P(State), Start),
    {true, Req, State};

write(Req, State = #state{path = [Hypervisor, <<"characteristics">> | Path]}, [{K, V}]) ->
    Start = now(),
    libsniffle:hypervisor_set(Hypervisor, [<<"characteristics">> | Path] ++ [K], jsxd:from_list(V)),
    ?MSniffle(?P(State), Start),
    {true, Req, State};

write(Req, State = #state{path = [Hypervisor, <<"metadata">> | Path]}, [{K, V}]) ->
    Start = now(),
    libsniffle:hypervisor_set(Hypervisor, [<<"metadata">> | Path] ++ [K], jsxd:from_list(V)),
    ?MSniffle(?P(State), Start),
    {true, Req, State};

write(Req, State = #state{path = [Hypervisor, <<"services">>]},
      [{<<"action">>, <<"enable">>},
       {<<"service">>, Service}]) ->
    libsniffle:hypervisor_service_action(Hypervisor, enable, Service),
    {true, Req, State};

write(Req, State = #state{path = [Hypervisor, <<"services">>]},
      [{<<"action">>, <<"disable">>},
       {<<"service">>, Service}]) ->
    libsniffle:hypervisor_service_action(Hypervisor, disable, Service),
    {true, Req, State};

write(Req, State = #state{path = [Hypervisor, <<"services">>]},
      [{<<"action">>, <<"clear">>},
       {<<"service">>, Service}]) ->
    libsniffle:hypervisor_service_action(Hypervisor, clear, Service),
    {true, Req, State};

write(Req, State, _Body) ->
    {false, Req, State}.


%%--------------------------------------------------------------------
%% DELETE
%%--------------------------------------------------------------------

delete(Req, State = #state{path = [Hypervisor, <<"characteristics">> | Path]}) ->
    Start = now(),
    libsniffle:hypervisor_set(Hypervisor, [<<"characteristics">> | Path], delete),
    ?MSniffle(?P(State), Start),
    {true, Req, State};

delete(Req, State = #state{path = [Hypervisor, <<"metadata">> | Path]}) ->
    Start = now(),
    libsniffle:hypervisor_set(Hypervisor, [<<"metadata">> | Path], delete),
    ?MSniffle(?P(State), Start),
    {true, Req, State}.
