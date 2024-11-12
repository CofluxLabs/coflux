defmodule Coflux.TopicUtils do
  def build_value(value) do
    case value do
      {:raw, data, references} ->
        %{
          type: "raw",
          data: data,
          references: build_references(references)
        }

      {:blob, key, size, references} ->
        %{
          type: "blob",
          key: key,
          size: size,
          references: build_references(references)
        }
    end
  end

  defp build_references(references) do
    Enum.map(references, fn
      {:fragment, serialiser, blob_key, size, metadata} ->
        %{
          type: "fragment",
          serialiser: serialiser,
          blobKey: blob_key,
          size: size,
          metadata: metadata
        }

      {:execution, execution_id, execution} ->
        %{
          type: "execution",
          executionId: Integer.to_string(execution_id),
          execution: build_execution(execution)
        }

      {:asset, asset_id, asset} ->
        %{
          type: "asset",
          assetId: Integer.to_string(asset_id),
          asset: build_asset(asset)
        }
    end)
  end

  def build_asset(asset) do
    %{
      type: asset.type,
      path: asset.path,
      metadata: asset.metadata,
      blobKey: asset.blob_key,
      size: asset.size,
      createdAt: asset.created_at
    }
  end

  def build_execution(execution) do
    %{
      runId: execution.run_id,
      stepId: execution.step_id,
      attempt: execution.attempt,
      repository: execution.repository,
      target: execution.target
    }
  end
end
