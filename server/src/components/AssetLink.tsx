import { Fragment, ReactNode, MouseEvent, useCallback, useState } from "react";
import { IconDownload, IconX } from "@tabler/icons-react";
import * as zip from "@zip.js/zip.js";

import * as models from "../models";
import { getAssetMetadata, readZipContents } from "../assets";
import { humanSize } from "../utils";

type Props = {
  asset: models.Asset;
  className?: string;
  children: ReactNode;
};

export default function AssetLink({ asset, className, children }: Props) {
  const mimeType = asset.type == 0 ? asset.metadata["type"] : undefined;
  const preview =
    asset.type == 1 ||
    mimeType?.startsWith("image/") ||
    mimeType?.startsWith("text/");
  const [open, setOpen] = useState<boolean>(false);
  const [content, setContent] = useState<
    ["image", string] | ["text", string] | ["zip", zip.Entry[]]
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
                if (asset.type == 1) {
                  return resp.blob().then((blob) => {
                    const blobReader = new zip.BlobReader(blob);
                    const zipReader = new zip.ZipReader(blobReader);
                    return zipReader.getEntries().then((entries) => {
                      setContent(["zip", entries]);
                    });
                  });
                } else if (mimeType?.startsWith("image/")) {
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
            <div className="absolute top-2 right-2 flex gap-2">
              <a
                href={`/blobs/${asset.blobKey}`}
                target="_blank"
                className="bg-slate-100/50 hover:bg-slate-300/50 p-1 rounded-md"
                title="Download"
              >
                <IconDownload size={20} />
              </a>
              <button
                onClick={handleCloseClick}
                className="bg-slate-100/50 hover:bg-slate-300/50 p-1 rounded-md"
                title="Close preview"
              >
                <IconX size={20} />
              </button>
            </div>
            <div className="overflow-auto flex-1">
              {content?.[0] == "image" ? (
                <img
                  src={content[1]}
                  className="max-w-auto max-h-full m-auto"
                />
              ) : content?.[0] == "text" ? (
                <pre className="p-3">{content[1]}</pre>
              ) : content?.[0] == "zip" ? (
                <div className="p-3">
                  <table className="w-full">
                    <tbody>
                      {content[1].map((entry) => (
                        <tr key={entry.filename}>
                          <td>{entry.filename}</td>
                          <td className="text-slate-500">
                            {humanSize(entry.uncompressedSize)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p>Loading...</p>
              )}
            </div>
          </div>
        </div>
      )}
      <a
        href={`/blobs/${asset.blobKey}`}
        title={`${asset.path}\n${getAssetMetadata(asset).join("; ")}`}
        className={className}
        target={"_blank"}
        onClick={handleClick}
      >
        {children}
      </a>
    </Fragment>
  );
}
