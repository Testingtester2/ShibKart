// Generate the resultSigner keypair for ShibKart tournaments.
//   node tools/gen-signer.mjs
// The PRIVATE KEY goes ONLY into the Supabase secret RESULT_SIGNER_KEY.
// The ADDRESS is the constructor arg when you deploy ShibKartTournament.sol.
import * as secp from "@noble/secp256k1";
import { keccak_256 } from "@noble/hashes/sha3";
const priv = secp.utils.randomPrivateKey();
const pub = secp.getPublicKey(priv, false);          // uncompressed (65 bytes)
const addr = "0x" + Buffer.from(keccak_256(pub.slice(1))).slice(12).toString("hex");
console.log("RESULT_SIGNER_KEY  (Supabase secret, hex, NO 0x):");
console.log("   " + Buffer.from(priv).toString("hex"));
console.log("resultSigner ADDRESS (ShibKartTournament constructor arg):");
console.log("   " + addr);
