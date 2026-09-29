import type { Metadata } from "next";
import ParallaxMotion from "./ParallaxMotion";
import ResultComparison from "./ResultComparison";

export const dynamic = "force-static";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

export const metadata: Metadata = {
  title: "Granular — A film finish for still images",
  description: "A native Mac app for giving still photographs a softer, warmer finish.",
};

export default function Home() {
  return (
    <main className="journal">
      <ParallaxMotion />
      <nav className="masthead">
        <a className="journal-mark" href="#top" aria-label="Granular home"><img src={asset("/app-icon-dark.png?v=3")} alt="" /> GRANULAR</a>
        <a href="https://github.com/dmccullum/Granular">GITHUB ↗</a>
      </nav>

      <section className="opening" id="top">
        <div className="opening-words" data-parallax="10" aria-label="Give your photos a film-like finish">
          <span>Give your</span><span>photos a</span><em>film-like finish.</em>
        </div>
        <figure className="opening-frame" data-parallax="-24">
          <img src={asset("/film-canister-hero.png")} alt="A 35mm film canister with a curling strip of film" />
        </figure>
        <div className="opening-action">
          <p>A native macOS app for adding film-like halation, grain, and more to your images. Pick a recipe, drop your photos on the film, and they’re done.</p>
          <a className="stamp stamp-yellow" href="https://github.com/dmccullum/Granular">GET GRANULAR <b>↗</b></a>
        </div>
      </section>

      <section className="workbench">
        <div className="workbench-words"><span>Drop photos in</span><em>for instant results,</em><span>or edit live.</span></div>
        <div className="workbench-views">
          <figure className="app-frame edit-frame" data-parallax="-18">
            <img src={asset("/granular-edit.webp?v=3")} alt="Granular Edit mode with live preview and adjustment panels" />
          </figure>
          <figure className="app-frame instant-frame" data-parallax="14">
            <img src={asset("/granular-instant.webp?v=3")} alt="Granular Instant mode: a film canister and a strip of frames to drop images onto" />
          </figure>
        </div>
      </section>

      <section className="ingredients-scatter">
        <h2>Tools for a<br /><em>film-like finish.</em></h2>
        <article className="ingredient tone-card" data-parallax="-14"><span>01</span><h3>FILM TONE</h3><p>Color stock, exposure, contrast, saturation, vibrance, and warmth—shaped with a gentler response.</p></article>
        <article className="ingredient vignette-card" data-parallax="11"><span>02</span><h3>VIGNETTE</h3><p>Set the frame’s falloff and focus with a photographic, lens-like vignette.</p></article>
        <article className="ingredient lens-blur-card" data-parallax="-10"><span>03</span><h3>LENS BLUR</h3><p>Off-axis optical blur with optional prismatic RGB separation.</p></article>
        <article className="ingredient diffusion-card" data-parallax="13"><span>04</span><h3>DIFFUSION</h3><p>Black Pro-Mist-style bloom that gathers around the light.</p></article>
        <article className="ingredient halation-card" data-parallax="-12"><span>05</span><h3>HALATION</h3><p>A restrained warm spill where bright light meets the darker world.</p></article>
        <article className="ingredient glow-card" data-parallax="-9"><span>06</span><h3>LANDSCAPE GLOW</h3><p>Detail-preserving softness that lifts the light without flattening the shadows.</p></article>
        <article className="ingredient grain-card" data-parallax="10"><span>07</span><h3>FILM GRAIN</h3><p>Light-responsive texture with scale, variation, chroma, and character.</p></article>
      </section>

      <section className="comparison-story">
        <div className="comparison-intro"><h2>See the <em>results.</em></h2></div>
        <ResultComparison />
      </section>

      <section className="last-frame">
        <img src={asset("/app-icon-dark.png?v=3")} alt="Granular app icon" />
        <h2>Made with love<br />by <a href="https://danielm.cc">Daniel McCullum</a></h2>
        <a className="stamp stamp-red" href="https://github.com/dmccullum/Granular">VIEW ON GITHUB ↗</a>
      </section>
      <footer><span>GRANULAR / 2026</span><a href="#top">BACK TO TOP ↑</a></footer>
    </main>
  );
}
