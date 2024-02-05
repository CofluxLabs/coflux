import { Fragment, ReactNode, MouseEvent, useCallback, useState } from "react";
import { IconX } from "@tabler/icons-react";

import * as models from "../models";
import { humanSize, pluralise } from "../utils";

function formatMetadata(asset: models.Asset) {
  const parts = [];
  switch (asset.type) {
    case 0:
      if ("size" in asset.metadata) {
        parts.push(humanSize(asset.metadata.size));
      }
      if ("type" in asset.metadata && asset.metadata.type) {
        parts.push(asset.metadata.type);
      }
      break;
    case 1:
      if ("count" in asset.metadata) {
        parts.push(pluralise(asset.metadata.count, "file"));
      }
      if ("totalSize" in asset.metadata) {
        parts.push(humanSize(asset.metadata.totalSize));
      }
      break;
  }
  return parts.join("; ");
}

type Props = {
  asset: models.Asset;
  className?: string;
  children: ReactNode;
};

export default function AssetLink({ asset, className, children }: Props) {
  const mimeType = asset.type == 0 ? asset.metadata["type"] : undefined;
  const preview =
    mimeType?.startsWith("image/") || mimeType?.startsWith("text/");
  const [open, setOpen] = useState<boolean>(false);
  const [content, setContent] = useState<
    ["image", string] | ["text", string]
  >();
  const handleClick = useCallback(
    (ev: MouseEvent) => {
      if (!ev.ctrlKey && preview) {
        ev.preventDefault();
        // TODO: confirm for large file?
        setOpen(true);
        if (!content) {
          fetch(`/blobs/${asset.blobKey}`)
            .then((resp) => {
              if (resp.ok) {
                if (mimeType?.startsWith("image/")) {
                  return resp.blob().then((blob) => {
                    const url = URL.createObjectURL(blob);
                    setContent(["image", url]);
                  });
                } else {
                  return resp.text().then((text) => {
                    setContent(["text", text]);
                  });
                }
              } else {
                return Promise.reject();
              }
            })
            .catch(() => {
              alert("Failed to load blob.");
            });
        }
      }
    },
    [content, mimeType],
  );
  const handleCloseClick = useCallback(() => {
    setOpen(false);
  }, []);
  return (
    <Fragment>
      {open && (
        <div className="z-30 fixed inset-0 flex">
          <div
            className="absolute bg-black/60 inset-0"
            onClick={handleCloseClick}
          />
          <div className="relative bg-white rounded-lg shadow-xl overflow-hidden m-auto min-w-[40vw] min-h-[30vh] max-w-[85vw] max-h-[85vh] flex">
            <button
              onClick={handleCloseClick}
              className="absolute top-2 right-2 bg-slate-100/50 hover:bg-slate-300/50 p-1 rounded-md"
            >
              <IconX size={28} />
            </button>
            <div className="overflow-auto">
              {content?.[0] == "image" ? (
                <img src={content[1]} className="m-auto" />
              ) : content?.[0] == "text" ? (
                <pre className="p-3">{content[1]}</pre>
              ) : (
                <p>Loading...</p>
              )}
            </div>
          </div>
        </div>
      )}
      <a
        href={`/blobs/${asset.blobKey}`}
        title={`${asset.path}\n${formatMetadata(asset)}`}
        className={className}
        target={"_blank"}
        onClick={handleClick}
      >
        {children}
      </a>
    </Fragment>
  );
}
