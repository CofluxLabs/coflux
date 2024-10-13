import {
  Fragment,
  ReactNode,
  MouseEvent,
  useCallback,
  useState,
  useEffect,
} from "react";
import {
  IconCornerLeftUp,
  IconDownload,
  IconFile,
  IconFolder,
} from "@tabler/icons-react";

import * as models from "../models";
import { getAssetMetadata } from "../assets";
import { humanSize, pluralise } from "../utils";
import Dialog from "./common/Dialog";
import { uniq } from "lodash";
import usePrevious from "../hooks/usePrevious";

type Entry = { path: string; size: number; type: string };

function showPreview(mimeType: string | undefined) {
  const parts = mimeType?.split("/");
  switch (parts?.[0]) {
    case "image":
    case "text":
      return true;
    default:
      return false;
  }
}

function assetUrl(projectId: string, assetId: string, path?: string) {
  return `/assets/${projectId}/${assetId}${path ? `/${path}` : ""}`;
}

function pathParent(path: string) {
  return path.includes("/") ? path.substring(path.lastIndexOf("/") + 1) : "";
}

type FilePreviewProps = {
  open: boolean;
  projectId: string;
  assetId: string;
  path?: string;
  type?: string;
  size?: number;
  onClose: () => void;
};

function PreviewDialog({
  open,
  projectId,
  assetId,
  path,
  type,
  size,
  onClose,
}: FilePreviewProps) {
  if (showPreview(type)) {
    return (
      <Dialog open={open} className="max-w-[80vw] h-[80vh]" onClose={onClose}>
        <div className="h-full rounded-lg overflow-hidden flex flex-col min-w-2xl">
          <iframe
            src={assetUrl(projectId, assetId, path)}
            sandbox="allow-downloads allow-forms allow-modals allow-scripts"
            className="size-full"
          />
        </div>
      </Dialog>
    );
  } else {
    return (
      <Dialog open={open} className="p-6 max-w-sm" onClose={onClose}>
        <div className="flex justify-center">
          <a
            href={assetUrl(projectId, assetId, path)}
            className="flex flex-col items-center hover:bg-slate-100 rounded-md px-3 py-1"
            target="_blank"
          >
            <IconDownload size={30} />
            {size !== undefined && humanSize(size)}
          </a>
        </div>
      </Dialog>
    );
  }
}

type EntriesTableProps = {
  entries: Entry[];
  path: string;
  projectId: string;
  assetId: string;
  onSelect: (path: string) => void;
};

function EntriesTable({
  entries,
  path,
  projectId,
  assetId,
  onSelect,
}: EntriesTableProps) {
  const pathEntries = entries.filter((e) => e.path.startsWith(path));
  const directories = uniq(
    pathEntries
      .map((e) => e.path.substring(path.length))
      .filter((e) => e.includes("/"))
      .map((p) => p.substring(0, p.indexOf("/") + 1)),
  );
  const files = pathEntries.filter(
    (e) => !e.path.substring(path.length).includes("/"),
  );
  return (
    <table className="w-full">
      <tbody>
        {path && (
          <tr>
            <td>
              <button
                className="inline-flex gap-1 items-center mb-1 rounded px-1 hover:bg-slate-100"
                onClick={() => onSelect(pathParent(path))}
              >
                <IconCornerLeftUp size={16} /> Up
              </button>
            </td>
            <td></td>
          </tr>
        )}
        {directories.map((directory) => (
          <tr key={directory}>
            <td>
              <button
                onClick={() => onSelect(`${path}${directory}`)}
                className="inline-flex gap-1 items-center rounded px-1 hover:bg-slate-100"
              >
                <IconFolder size={16} />
                {directory}
              </button>
            </td>
            <td></td>
          </tr>
        ))}
        {files.map((entry) => (
          <tr key={entry.path}>
            <td>
              <a
                href={assetUrl(projectId, assetId, entry.path)}
                className="inline-flex gap-1 items-center rounded px-1 hover:bg-slate-100"
                onClick={(ev) => {
                  if (!ev.ctrlKey) {
                    ev.preventDefault();
                    onSelect(entry.path);
                  }
                }}
              >
                <IconFile size={16} />
                {entry.path.substring(path.length)}
              </a>
            </td>
            <td className="text-slate-500">{humanSize(entry.size)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

type DirectoryBrowserProps = {
  open: boolean;
  asset: models.Asset;
  projectId: string;
  assetId: string;
  onClose: () => void;
};

function DirectoryBrowser({
  open,
  asset,
  projectId,
  assetId,
  onClose,
}: DirectoryBrowserProps) {
  const [entries, setEntries] = useState<Entry[]>();
  const [directory, setDirectory] = useState("");
  const [entry, setEntry] = useState<Entry>();
  const previousEntry = usePrevious(entry);
  useEffect(() => {
    if (open) {
      fetch(`/assets/${projectId}/${assetId}`)
        .then((resp) => resp.json())
        .then((entries) => {
          setEntries(entries);
        })
        .catch((error) => {
          // TODO
          console.log("*e", error);
        });
    }
  }, [projectId, assetId, open || !!entries]);
  const handleSelect = useCallback(
    (path: string) => {
      if (path == "" || path.endsWith("/")) {
        setDirectory(path);
      } else {
        setEntry(entries?.find((e) => e.path == path));
      }
    },
    [entries],
  );
  const handlePreviewClose = useCallback(() => setEntry(undefined), []);
  return (
    <>
      <Dialog
        open={open}
        title={
          <div>
            {asset.path}/{" "}
            <span className="text-slate-500 font-normal text-lg">
              ({pluralise(asset.metadata["count"], "file")})
            </span>
          </div>
        }
        className={"p-6 max-w-lg"}
        onClose={onClose}
      >
        <div className="flex flex-col">
          {entries ? (
            <div className="">
              <EntriesTable
                entries={entries}
                path={directory}
                projectId={projectId}
                assetId={assetId}
                onSelect={handleSelect}
              />
            </div>
          ) : (
            <p>Loading...</p>
          )}
        </div>
        <PreviewDialog
          open={!!entry}
          projectId={projectId}
          assetId={assetId}
          path={(entry || previousEntry)?.path}
          type={(entry || previousEntry)?.type}
          size={(entry || previousEntry)?.size}
          onClose={handlePreviewClose}
        />
      </Dialog>
    </>
  );
}

type Props = {
  asset: models.Asset;
  projectId: string;
  assetId: string;
  className?: string;
  children: ReactNode;
};

export default function AssetLink({
  asset,
  projectId,
  assetId,
  className,
  children,
}: Props) {
  const [open, setOpen] = useState<boolean>(false);
  const handleLinkClick = useCallback((ev: MouseEvent) => {
    if (!ev.ctrlKey) {
      ev.preventDefault();
      setOpen(true);
    }
  }, []);
  const handleClose = useCallback(() => setOpen(false), []);
  return (
    <Fragment>
      {asset.type == 0 ? (
        <PreviewDialog
          open={open}
          projectId={projectId}
          assetId={assetId}
          type={asset.metadata["type"]}
          size={asset.metadata["size"]}
          onClose={handleClose}
        />
      ) : asset.type == 1 ? (
        <DirectoryBrowser
          open={open}
          asset={asset}
          projectId={projectId}
          assetId={assetId}
          onClose={handleClose}
        />
      ) : null}
      <a
        href={`/blobs/${asset.blobKey}`}
        title={`${asset.path}\n${getAssetMetadata(asset).join("; ")}`}
        className={className}
        target="_blank"
        onClick={handleLinkClick}
      >
        {children}
      </a>
    </Fragment>
  );
}
