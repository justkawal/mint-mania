import { db } from "@/db";
import type { tokens } from "@/db/drizzle/schema";
import React from "react";

export async function TokenHolders({ token }: { token: typeof tokens.$inferSelect }) {
  const holders = await db.query.holders.findMany({
    where: (holders, { eq }) => eq(holders.tokenId, token.id),
    orderBy: (holders, { desc }) => [desc(holders.balance)]
  });

  if (holders.length === 0) {
    return null;
  }

  return (
    <div className="w-full">
      <h1 className="text-2xl mb-4">HODLERS</h1>

      {holders.map((hodler) => (
        <div className="flex justify-between my-4 text-lg" key={hodler.id}>
          <a target="_blank" href={`https://sepolia.basescan.org/address/${hodler.address}`}>{hodler.address}</a>
          <span>{(Number(hodler.balance) / 10_000_000).toFixed(3)}%</span>
        </div>
      ))}
    </div>
  );
}
