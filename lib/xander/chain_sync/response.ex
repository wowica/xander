defmodule Xander.ChainSync.Response do
  @moduledoc """
  This module is responsible for decoding CBOR responses and parsing them into Ouroboros-specific structs.
  """
  alias Xander.Util

  require Logger

  # See https://www.rfc-editor.org/rfc/rfc8949.html#section-3.4
  @encoded_cbor_data_tag 24

  def parse_response(response) do
    case Util.plex(response) do
      {:ok, %{payload: response_payload}} ->
        decode(response_payload)

      _ ->
        {:error, "Failed to parse response"}
    end
  end

  defmodule Block do
    defstruct [:bytes, :hash, :slot_number]
  end

  defmodule Header do
    defstruct [:block_body_size, :block_number, :bytes]
  end

  defmodule IntersectFound do
    @type t() :: %__MODULE__{}
    defstruct [:point, :tip]
  end

  defmodule RollBackward do
    @type t() :: %__MODULE__{}
    defstruct [:point, :tip]
  end

  defmodule RollForward do
    @type t() :: %__MODULE__{}
    defstruct [:header, :tip]
  end

  defmodule AwaitReply do
    @type t() :: %__MODULE__{}
    defstruct []
  end

  @doc """
  Decodes a CBOR payload and returns a Ouroboros-specific struct.
  This function should be used in favor of using CBOR.decode/1 from the CBOR hex package directly.
  """
  @spec decode(cbor :: binary()) ::
          {:ok,
           AwaitReply.t()
           | RollForward.t()
           | RollBackward.t()
           | IntersectFound.t()}
          | {:error, any()}
  def decode(cbor_data) do
    case CBOR.decode(cbor_data) do
      {:ok, [1], _rest} ->
        {:ok, %AwaitReply{}}

      {:ok, [2, header, tip], _rest} ->
        with {:ok, parsed_header} <- parse_header(header),
             {:ok, parsed_tip} <- parse_block(tip) do
          {:ok, %RollForward{header: parsed_header, tip: parsed_tip}}
        end

      {:ok, [3, point, tip], _rest} ->
        with {:ok, parsed_point} <- parse_point(point),
             {:ok, parsed_block} <- parse_block(tip) do
          {:ok, %RollBackward{point: parsed_point, tip: parsed_block}}
        end

      {:ok, [5, point, tip], _rest} ->
        with {:ok, parsed_point} <- parse_point(point),
             {:ok, parsed_block} <- parse_block(tip) do
          {:ok, %IntersectFound{point: parsed_point, tip: parsed_block}}
        end

      {:ok, unknown_response, _rest} ->
        Logger.warning("Unknown response: #{inspect(unknown_response)}")
        {:error, :unknown_response}

      {:error, _} ->
        {:error, :incomplete_cbor_data}
    end
  end

  # Parses a decoded CBOR header into a Header struct.
  # The input should be a decoded CBOR Tag containing the header data.
  defp parse_header(header) do
    %CBOR.Tag{
      tag: @encoded_cbor_data_tag,
      value: %CBOR.Tag{
        tag: :bytes,
        value: header_bytes
      }
    } = header

    case CBOR.decode(header_bytes) do
      {:ok,
       [
         _idk_what_this_is,
         [[[block_number, _, _, _, _, _, block_body_size | _] | _] | _] | _signature
       ], _rest} ->
        {:ok,
         %Header{
           block_number: block_number,
           block_body_size: block_body_size,
           bytes: header_bytes
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_block(block) do
    [[slot_number, block_payload], _block_height] = block

    %CBOR.Tag{
      tag: :bytes,
      value: block_bytes
    } = block_payload

    {:ok,
     %Block{
       slot_number: slot_number,
       hash: Base.encode16(block_bytes, case: :lower),
       bytes: block_bytes
     }}
  end

  defp parse_point([]) do
    {:ok, %{}}
  end

  defp parse_point(point) do
    [
      slot_number,
      %CBOR.Tag{tag: :bytes, value: block_bytes}
    ] = point

    rollback_block_hash = Base.encode16(block_bytes, case: :lower)

    {:ok,
     %Block{
       slot_number: slot_number,
       hash: rollback_block_hash,
       bytes: block_bytes
     }}
  end
end
