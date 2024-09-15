defmodule Coflux.Handlers.Assets do
  import Coflux.Handlers.Utils

  alias Coflux.Utils
  alias Coflux.Orchestration

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    path = :cowboy_req.path_info(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:asset], path, opts)
  end

  defp handle(req, "GET", project_id, asset_id, path, opts) do
    asset_id = String.to_integer(asset_id)

    # TODO: support other blob stores?
    req =
      case Orchestration.get_asset(project_id, asset_id, load_metadata: true) do
        {:ok, asset_type, _path, blob_key, metadata} ->
          cond do
            asset_type == 0 && path == [] ->
              content_type = Map.get(metadata, "type", "application/octet-stream")

              case File.read(blob_path(blob_key)) do
                {:ok, content} ->
                  :cowboy_req.reply(
                    200,
                    %{"content-type" => content_type},
                    content,
                    req
                  )
              end

            asset_type == 1 ->
              {:ok, unzip} =
                blob_key
                |> blob_path()
                |> Unzip.LocalFile.open()
                |> Unzip.new()

              path = Enum.join(path, "/")

              paths =
                unzip
                |> Unzip.list_entries()
                |> Map.new(&{&1.file_name, &1.uncompressed_size})

              cond do
                path == "" ->
                  :cowboy_req.reply(
                    200,
                    %{"content-type" => "application/json"},
                    Jason.encode!(
                      Enum.map(paths, fn {path, size} ->
                        %{path: path, size: size, type: MIME.from_path(path)}
                      end)
                    ),
                    req
                  )

                Map.has_key?(paths, path) ->
                  mime_type = MIME.from_path(path)
                  req = :cowboy_req.stream_reply(200, %{"content-type" => mime_type}, req)

                  unzip
                  |> Unzip.file_stream!(path)
                  |> Stream.each(fn part ->
                    :cowboy_req.stream_body(part, :nofin, req)
                  end)
                  |> Stream.run()

                  :cowboy_req.stream_body([], :fin, req)

                  req

                true ->
                  :cowboy_req.reply(404, %{}, "Not found", req)
              end

            true ->
              :cowboy_req.reply(404, %{}, "Not found", req)
          end

        {:error, _error} ->
          :cowboy_req.reply(404, %{}, "Not found", req)
      end

    {:ok, req, opts}
  end

  defp blob_path(<<a::binary-size(2), b::binary-size(2)>> <> c) do
    Utils.data_path("blobs/#{a}/#{b}/#{c}")
  end
end
