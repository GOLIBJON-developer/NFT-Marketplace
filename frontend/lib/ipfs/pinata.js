import { pinataConfig } from "../contracts/config";

//------------------------------------------------------------------------------------
export const uploadToPinata = async (file) => {
  try {
    const jwt = pinataConfig.jwt;
    if (!jwt) throw new Error("NEXT_PUBLIC_PINATA_JWT not set");

    const form = new FormData();
    form.append("file", file);
    form.append("name", `nft-${Date.now()}-${file.name}`);
    form.append("network", "public"); // ← muhim: public qilib yuklash

    const res = await fetch("https://uploads.pinata.cloud/v3/files", {
      method: "POST",
      headers: { Authorization: `Bearer ${jwt}` },
      body: form,
    });

    if (!res.ok) throw new Error(`Pinata: ${await res.text()}`);

    const data = await res.json();
    const cid = data?.data?.cid;
    if (!cid) throw new Error("No CID returned from Pinata");

    return {
      hash: cid,
      url: `${pinataConfig.gatewayUrl}${cid}`,
    };
  } catch (error) {
    throw new Error(`Pinata upload failed: ${error.message}`);
  }
};

export const uploadMetadataToPinata = async (metadata) => {
  try {
    const jwt = pinataConfig.jwt;
    if (!jwt) throw new Error("NEXT_PUBLIC_PINATA_JWT not set");

    // JSON ni File sifatida v3 ga yuklash
    const blob = new Blob([JSON.stringify(metadata)], {
      type: "application/json",
    });
    const file = new File([blob], `metadata-${Date.now()}.json`, {
      type: "application/json",
    });

    const form = new FormData();
    form.append("file", file);
    form.append("name", `nft-metadata-${metadata.name}-${Date.now()}`);
    form.append("network", "public");

    const res = await fetch("https://uploads.pinata.cloud/v3/files", {
      method: "POST",
      headers: { Authorization: `Bearer ${jwt}` },
      body: form,
    });

    if (!res.ok) throw new Error(`Pinata: ${await res.text()}`);

    const data = await res.json();
    const cid = data?.data?.cid;
    if (!cid) throw new Error("No CID returned from Pinata");

    return {
      hash: cid,
      url: `${pinataConfig.gatewayUrl}${cid}`,
    };
  } catch (error) {
    throw new Error(`Metadata upload failed: ${error.message}`);
  }
};

export const fetchMetadataFromIPFS = async (tokenURI) => {
  if (!tokenURI) throw new Error("No token URI provided");

  const hash = tokenURI.startsWith("ipfs://")
    ? tokenURI.slice(7)
    : tokenURI.replace(/^\/+/, "");

  // Dedicated gateway birinchi, keyin fallback lar
  const gateways = [
  "https://ipfs.io/ipfs/",          // ← birinchi
  "https://gateway.pinata.cloud/ipfs/",
  "https://dweb.link/ipfs/",
  "https://nftstorage.link/ipfs/",
];

  let lastError;

  for (const gateway of gateways) {
    try {
      const url = tokenURI.startsWith("http") ? tokenURI : `${gateway}${hash}`;
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000);

      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const text = await response.text();
      try {
        return JSON.parse(text);
      } catch {
        throw new Error("Invalid JSON response");
      }
    } catch (error) {
      lastError = error;
    }
  }

  // Fallback
  const tokenId = tokenURI.match(/(\d+)/)?.[0] || "Unknown";
  return {
    name: `NFT #${tokenId}`,
    description: "Metadata temporarily unavailable.",
    image: "",
    attributes: [],
    collection: "Unknown Collection",
    error: true,
    originalURI: tokenURI,
  };
};

// Helper function to validate metadata structure
export const validateMetadata = (metadata) => {
  const requiredFields = ["name"];
  const validMetadata = { ...metadata };

  // Ensure required fields exist
  requiredFields.forEach((field) => {
    if (!validMetadata[field]) {
      validMetadata[field] = `Unknown ${field}`;
    }
  });

  // Ensure optional fields have defaults
  if (!validMetadata.description) validMetadata.description = "";
  if (!validMetadata.image) validMetadata.image = "";
  if (!validMetadata.attributes) validMetadata.attributes = [];
  if (!validMetadata.collection)
    validMetadata.collection = "Unnamed Collection";

  return validMetadata;
};



export const getImageUrl = (imageUri) => {
  if (!imageUri) return "";
  
  const toPublicGateway = (cid) => `https://ipfs.io/ipfs/${cid}`;

  if (imageUri.startsWith("ipfs://")) return toPublicGateway(imageUri.slice(7));
  if (imageUri.startsWith("Qm") || imageUri.startsWith("baf")) return toPublicGateway(imageUri);
  if (imageUri.startsWith("http")) return imageUri;
  return toPublicGateway(imageUri);
};