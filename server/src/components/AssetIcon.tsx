import { IconFile, IconFileText, IconFolder } from "@tabler/icons-react";

import * as models from "../models";

function iconForAsset(asset: models.Asset) {
  switch (asset.type) {
    case 0:
      const type = asset.metadata["type"];
      switch (type?.split("/")[0]) {
        case "text":
          return IconFileText;
        default:
          return IconFile;
      }
    case 1:
      return IconFolder;
    default:
      throw new Error(`unrecognised asset type (${asset.type})`);
  }
}

type AssetIconProps = {
  asset: models.Asset;
  size?: number;
  className?: string;
};

export default function AssetIcon({
  asset,
  size = 16,
  className,
}: AssetIconProps) {
  const Icon = iconForAsset(asset);
  return <Icon size={size} className={className} />;
}
