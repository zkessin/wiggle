-module(wiggle_handler).

-include("wiggle.hrl").

-export([
         initial_state/1,
         provided/0,
         accepted/0,
         decode/1,
         get_token/1,
         set_access_header/1,
         allowed/2,
         options/3,
         service_available/0,
         encode/2
        ]).

initial_state(Req) ->
    {Method, Req0} = cowboy_req:method(Req),
    {Version, Req1} = cowboy_req:binding(version, Req0),
    {Path, Req2} = cowboy_req:path_info(Req1),
    {Token, Req3} = get_token(Req2),
    {PathB, Req4} = cowboy_req:path(Req3),
    {FullList, Req5} = full_list(Req4),
    {FullListFields, Req6} = full_list_fields(Req5),
    State =  #state{
                version = Version,
                method = Method,
                token = Token,
                path = Path,
                start = now(),
                path_bin = PathB,
                full_list = FullList,
                full_list_fields = FullListFields
               },
    {ok, set_access_header(Req6), State}.

set_access_header(Req) ->
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, <<"*">>, Req),
    Req2 = cowboy_req:set_resp_header(
             <<"access-control-allow-headers">>,
             <<"Authorization, content-type, x-snarl-token, x-full-list, x-full-fields">>, Req1),
    Req3 = cowboy_req:set_resp_header(
             <<"access-control-expose-headers">>,
             <<"x-snarl-token, x-full-list, x-full-fields">>, Req2),
    cowboy_req:set_resp_header(
      <<"allow-access-control-credentials">>,
      <<"true">>, Req3).

get_token(Req) ->
    case cowboy_req:header(<<"x-snarl-token">>, Req) of
        {undefined, ReqX} ->
            case cowboy_req:cookie(<<"x-snarl-token">>, ReqX) of
                {undefined, ReqX1} ->
                    case cowboy_req:header(<<"authorization">>, ReqX1) of
                        {undefined, ReqX2} ->
                            lager:warning("[auth] No authenticaiton req was: ~p.",
                                          [Req]),
                            {undefined, ReqX2};
                        {AuthorizationHeader, ReqX2} ->
                            Res = basic_auth(AuthorizationHeader),
                            {Res, ReqX2}
                    end;
                {TokenX, ReqX1} ->
                    {{token, TokenX}, ReqX1}
                end;
        {TokenX, ReqX} ->
            ReqX1 = cowboy_req:set_resp_header(<<"x-snarl-token">>, TokenX, ReqX),
            {{token, TokenX}, ReqX1}
    end.


basic_auth(AuthorizationHeader) ->
    case binary:split(AuthorizationHeader, <<$ >>) of
        [<<"Basic">>, EncodedCredentials] ->
            decoded_credentials(EncodedCredentials);
        _ ->
            undefined
    end.

decoded_credentials(EncodedCredentials) ->
    DecodedCredentials = base64:decode(EncodedCredentials),
    case binary:split(DecodedCredentials, <<$:>>) of
        [UUID, Password] ->
            case libsnarl:auth(UUID, Password) of
                {ok, UUID} ->
                    UUID;
                _ ->
                    lager:warning("[auth] Basic auth failed."),
                    undefined
            end;
        _ ->
            undefined
    end.


full_list(Req) ->
    case cowboy_req:header(<<"x-full-list">>, Req) of
        {<<"true">>, ReqX} ->
            {true, ReqX};
        {<<"True">>, ReqX} ->
            {true, ReqX};
        {_, ReqX} ->
            {false, ReqX}
    end.

full_list_fields(Req) ->
    case cowboy_req:header(<<"x-full-list-fields">>, Req) of
        {undefined, ReqX} ->
            {[], ReqX};
        {Fields, ReqX} ->
            {re:split(Fields, ","), ReqX}
    end.

provided() ->
    [
     {{<<"application">>, <<"x-msgpack">>, []}, read},
     {{<<"application">>, <<"json">>, []}, read}
    ].

accepted() ->
    [
     {{<<"application">>, <<"x-msgpack">>, '*'}, write},
     {{<<"application">>, <<"json">>, '*'}, write}
    ].

media_type(Req) ->
    case cowboy_req:meta(media_type, Req) of
        {{<<"application">>, <<"x-msgpack">>, _}, Req1} ->
            {msgpack, Req1};
        {{<<"application">>, <<"json">>, _}, Req1} ->
            {json, Req1};
        {_, Req1} ->
            {json, Req1}
    end.

decode(Req) ->
    {ContentType, Req0} = media_type(Req),
    {ok, Body, Req1} = cowboy_req:body(Req0),
    Decoded = case Body of
                  <<>> ->
                      [];
                  _ ->
                      case ContentType of
                          json ->
                              jsxd:from_list(jsx:decode(Body));
                          msgpack ->
                              {ok, D} = msgpack:unpack(Body, [jsx]),
                              jsxd:from_list(D)
                      end
              end,
    {ok, Decoded, Req1}.

encode(Body, Req) ->
    {ContentType, Req1} = media_type(Req),
    case ContentType of
        json ->
            {jsx:encode(Body), Req1};
        msgpack ->
            {msgpack:pack(Body, [jsx]), Req1}
    end.

options(Req, State, Methods) ->
    Req1 = cowboy_req:set_resp_header(
             <<"access-control-allow-methods">>,
             string:join(
               lists:map(fun erlang:binary_to_list/1,
                         [<<"HEAD">>, <<"OPTIONS">> | Methods]), ", "), Req),
    {ok, Req1, State}.

allowed(State = #state{token = Token}, Perm) ->
    Start = now(),
    R = case libsnarl:allowed(Token, Perm) of
            not_found ->
                lager:warning("[auth] unknown Token for allowed: ~p", [Token]),
                true;
            true ->
                false;
            false ->
                lager:warning("[auth] ~p is not allowed for: ~p", [Perm, Token]),
                true
        end,
    ?MSnarl(?P(State), Start),
    R.

service_available() ->
    case {libsniffle:servers(), libsnarl:servers()} of
        {[], _} ->
            false;
        {_, []} ->
            false;
        _ ->
            true
    end.
