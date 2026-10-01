import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Global presentation rules for the MP documentation.
class SiteSkin extends StatelessComponent {
  /// Creates the global site-skin component.
  const SiteSkin({super.key});

  @override
  Component build(BuildContext context) => Document.head(
    children: [
      const meta(name: 'theme-color', content: '#10110f'),
      const meta(
        name: 'description',
        content: 'API and package documentation for MediaPipe Tasks on Dart and Flutter.',
      ),
      Style(styles: styles),
    ],
  );

  /// CSS rules shared by every documentation route.
  static List<StyleRule> get styles => [
    css(':root').styles(
      raw: {
        '--mp-ink': '#171815',
        '--mp-paper': '#f4f1e8',
        '--mp-panel': '#e9e5da',
        '--mp-line': '#c8c1b1',
        '--mp-acid': '#c8ff32',
        '--mp-coral': '#ff694d',
        '--mp-muted': '#69695f',
      },
    ),
    css(':root[data-theme="dark"]').styles(
      raw: {
        '--mp-ink': '#f2efe6',
        '--mp-paper': '#10110f',
        '--mp-panel': '#1b1d19',
        '--mp-line': '#3b3e35',
        '--mp-muted': '#aaa99d',
      },
    ),
    css('html').styles(raw: {'scroll-behavior': 'smooth'}),
    css('body').styles(
      raw: {
        'font-family': '"Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif',
        'background-image':
            'linear-gradient(var(--mp-line) 1px, transparent 1px), linear-gradient(90deg, var(--mp-line) 1px, transparent 1px)',
        'background-size': '48px 48px',
        'background-attachment': 'fixed',
      },
    ),
    css('body::before').styles(
      raw: {
        'content': '""',
        'position': 'fixed',
        'inset': '0',
        'pointer-events': 'none',
        'background': 'var(--mp-paper)',
        'opacity': '.92',
        'z-index': '-1',
      },
    ),
    css('.header-container').styles(
      raw: {
        'background': 'color-mix(in srgb, var(--mp-paper) 88%, transparent)',
        'border-bottom': '1px solid var(--mp-line)',
      },
    ),
    css('.header').styles(raw: {'border': '0', 'max-width': '1600px'}),
    css('.header-title span').styles(
      raw: {'font-size': '1rem', 'font-weight': '800', 'letter-spacing': '-.04em'},
    ),
    css('.header-title img').styles(raw: {'width': '2rem', 'height': '2rem'}),
    css('.sidebar-container').styles(raw: {'background': 'var(--mp-paper)'}),
    css('.sidebar').styles(raw: {'border-right': '1px solid var(--mp-line)'}),
    css('.content-container').styles(
      raw: {
        'background': 'var(--mp-paper)',
        'border-left': '1px solid var(--mp-line)',
        'border-right': '1px solid var(--mp-line)',
        'padding': 'clamp(1.5rem, 4vw, 4.5rem)',
        'min-height': 'calc(100vh - 4rem)',
      },
    ),
    css('.content-header h1').styles(
      raw: {
        'font-size': 'clamp(2.6rem, 6vw, 5.8rem)',
        'line-height': '.93',
        'letter-spacing': '-.075em',
        'max-width': '900px',
      },
    ),
    css('.content-header p').styles(
      raw: {
        'max-width': '780px',
        'color': 'var(--mp-muted)',
        'font-size': 'clamp(1.05rem, 2vw, 1.35rem)',
        'line-height': '1.5',
      },
    ),
    css('.content h2').styles(
      raw: {
        'margin-top': '4rem',
        'padding-top': '1rem',
        'border-top': '1px solid var(--mp-line)',
        'font-size': 'clamp(1.8rem, 4vw, 3.2rem)',
        'letter-spacing': '-.055em',
      },
    ),
    css('.content h3').styles(
      raw: {'font-size': '1.25rem', 'letter-spacing': '-.025em'},
    ),
    css('.content a').styles(
      raw: {
        'text-decoration-color': 'var(--mp-coral)',
        'text-decoration-thickness': '2px',
        'text-underline-offset': '3px',
      },
    ),
    css('.content pre').styles(
      raw: {
        'border': '1px solid var(--mp-line)',
        'border-radius': '0',
        'box-shadow': '8px 8px 0 var(--mp-acid)',
      },
    ),
    css('.content table').styles(raw: {'display': 'table', 'width': '100%'}),
    css('.content th').styles(
      raw: {
        'text-transform': 'uppercase',
        'font-size': '.72rem',
        'letter-spacing': '.12em',
      },
    ),
    css('.content blockquote').styles(
      raw: {
        'border-left': '5px solid var(--mp-coral)',
        'background': 'var(--mp-panel)',
        'padding': '1rem 1.25rem',
      },
    ),
    css('.mp-package-grid').styles(
      raw: {
        'display': 'grid',
        'grid-template-columns': 'repeat(2, minmax(0, 1fr))',
        'gap': '1px',
        'border': '1px solid var(--mp-line)',
        'background': 'var(--mp-line)',
        'margin': '2rem 0',
      },
    ),
    css('.mp-package').styles(
      raw: {
        'display': 'block',
        'min-height': '150px',
        'padding': '1.4rem',
        'background': 'var(--mp-paper)',
        'color': 'var(--mp-ink)',
        'text-decoration': 'none',
      },
    ),
    css('.mp-package:hover').styles(raw: {'background': 'var(--mp-acid)', 'color': '#10110f'}),
    css('.mp-package code').styles(raw: {'font-size': '1.15rem', 'font-weight': '800'}),
    css('.mp-package span').styles(
      raw: {'display': 'block', 'margin-top': '.65rem', 'line-height': '1.45'},
    ),
    css.media(
      MediaQuery.all(maxWidth: 800.px),
      [
        css('.mp-package-grid').styles(raw: {'grid-template-columns': '1fr'}),
        css('.content-container').styles(raw: {'border-right': '0', 'border-left': '0'}),
      ],
    ),
  ];
}

/// A responsive package index for the homepage.
class PackageGrid extends StatelessComponent {
  /// Creates the homepage package grid.
  const PackageGrid({super.key});

  @override
  Component build(BuildContext context) {
    const List<(String, String, String)> packages = [
      ('mp_core', 'packages/core', 'Models, media containers, result types, lifecycle, and runtime support.'),
      ('mp_camera', 'packages/camera', 'Camera formats, rotation metadata, and latest-frame scheduling.'),
      (
        'mp_vision',
        'packages/vision',
        'Eleven detection, landmarking, classification, embedding, and segmentation tasks.',
      ),
      ('mp_text', 'packages/text', 'Detection, classification, embeddings, proofreading, and summarization.'),
      ('mp_audio', 'packages/audio', 'Clip and stream classification over immutable audio frames.'),
      (
        'mp_genai',
        'packages/genai',
        'LLM inference plus Android function calling, RAG, and image generation.',
      ),
    ];
    return div(classes: 'mp-package-grid', [
      for (final (String name, String href, String description) in packages)
        a(classes: 'mp-package', href: href, [
          code([Component.text(name)]),
          span([Component.text(description)]),
        ]),
    ]);
  }
}
