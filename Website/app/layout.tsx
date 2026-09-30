import type { Metadata } from "next";
import "./globals.css";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

export const metadata: Metadata = {
  title: "Granular — A photographic finish for still images",
  description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
  openGraph: {
    title: "Granular — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [{ url: asset("/app-icon-dark.png?v=5"), width: 1024, height: 1024, alt: "Granular app icon" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Granular — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [asset("/app-icon-dark.png?v=5")],
  },
  icons: {
    icon: { url: asset("/favicon.png?v=5"), type: "image/png", sizes: "64x64" },
    shortcut: asset("/favicon.png?v=5"),
    apple: { url: asset("/apple-touch-icon.png?v=5"), sizes: "180x180" },
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
