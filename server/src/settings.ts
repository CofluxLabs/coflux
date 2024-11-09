export type BlobStoreSettings =
  | {
      type: "http";
      protocol: "http" | "https";
      host: string;
    }
  | {
      type: "s3";
      bucket: string;
      prefix: string;
      region: string;
      accessKeyId: string;
      secretAccessKey: string;
    };

export type Settings = {
  blobStores: BlobStoreSettings[];
};
