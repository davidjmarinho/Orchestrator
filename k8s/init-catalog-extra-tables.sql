-- Orders table for catalog-api PlaceOrder endpoint
-- Column names must match EF Core model exactly (PlacedAtUtc, GameTitle, PriceCents, Currency)
CREATE TABLE IF NOT EXISTS "Orders" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "GameId" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "GameTitle" text,
    "PriceCents" integer NOT NULL DEFAULT 0,
    "Currency" text,
    "Status" integer NOT NULL DEFAULT 0,
    "PlacedAtUtc" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT "PK_Orders" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_Orders_GameId" ON "Orders" ("GameId");
CREATE INDEX IF NOT EXISTS "IX_Orders_UserId" ON "Orders" ("UserId");

-- LibraryItems table for user game library
CREATE TABLE IF NOT EXISTS "LibraryItems" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "GameId" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "AcquiredAtUtc" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT "PK_LibraryItems" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_LibraryItems_UserId" ON "LibraryItems" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_LibraryItems_GameId" ON "LibraryItems" ("GameId");
