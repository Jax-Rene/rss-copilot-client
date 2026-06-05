import 'package:rss_copilot_client/src/core/html_markdown.dart';
import 'package:test/test.dart';

void main() {
  group('htmlToMarkdown', () {
    test('converts common article HTML into markdown', () {
      final markdown = htmlToMarkdown('''
        <article>
          <h2>Section title</h2>
          <p>Hello <strong>world</strong>, read <a href="https://example.com">more</a>.</p>
          <blockquote><p>Important quote.</p></blockquote>
          <ul>
            <li>First point</li>
            <li>Second point</li>
          </ul>
          <pre><code>final value = 1;</code></pre>
          <figure>
            <img src="https://example.com/cover.jpg" alt="Cover" />
            <figcaption>Cover caption</figcaption>
          </figure>
        </article>
        ''');

      expect(
        markdown,
        '## Section title\n\n'
        'Hello **world**, read [more](https://example.com).\n\n'
        '> Important quote.\n\n'
        '- First point\n'
        '- Second point\n\n'
        '```\n'
        'final value = 1;\n'
        '```\n\n'
        '![Cover](https://example.com/cover.jpg)\n\n'
        'Cover caption',
      );
    });

    test('ignores empty html', () {
      expect(htmlToMarkdown('  '), isEmpty);
    });

    test('drops non-readable embedded content', () {
      final markdown = htmlToMarkdown('''
        <article>
          <p>Readable paragraph.</p>
          <script>window.track = true;</script>
          <style>.article { display: none; }</style>
          <noscript>Enable JavaScript.</noscript>
          <svg><title>Icon title</title></svg>
        </article>
        ''');

      expect(markdown, 'Readable paragraph.');
    });

    test('keeps article tables readable in markdown notes', () {
      final markdown = htmlToMarkdown('''
        <article>
          <p>Release matrix</p>
          <table>
            <thead>
              <tr><th>Plan</th><th>Status</th><th>Notes</th></tr>
            </thead>
            <tbody>
              <tr><td>Mac</td><td>Ready</td><td>Fast | stable</td></tr>
              <tr><td>Android</td><td>Next</td><td><strong>Beta</strong></td></tr>
            </tbody>
          </table>
          <hr>
          <p>Done.</p>
        </article>
        ''');

      expect(
        markdown,
        'Release matrix\n\n'
        '| Plan | Status | Notes |\n'
        '| --- | --- | --- |\n'
        r'| Mac | Ready | Fast \| stable |'
        '\n'
        '| Android | Next | **Beta** |\n\n'
        '---\n\n'
        'Done.',
      );
    });

    test('preserves nested list hierarchy', () {
      final markdown = htmlToMarkdown('''
        <article>
          <ol>
            <li>Open article
              <ul>
                <li>Copy note</li>
                <li>Review <strong>metadata</strong></li>
              </ul>
            </li>
            <li>Save to knowledge base</li>
          </ol>
        </article>
        ''');

      expect(
        markdown,
        '1. Open article\n'
        '  - Copy note\n'
        '  - Review **metadata**\n'
        '2. Save to knowledge base',
      );
    });

    test('preserves checkbox task list state', () {
      final markdown = htmlToMarkdown('''
        <article>
          <ul>
            <li><input type="checkbox" checked> Shipped OPML import</li>
            <li><input type="checkbox"> Polish reader shortcuts</li>
          </ul>
        </article>
        ''');

      expect(
        markdown,
        '- [x] Shipped OPML import\n'
        '- [ ] Polish reader shortcuts',
      );
    });

    test('keeps definition lists readable', () {
      final markdown = htmlToMarkdown('''
        <article>
          <dl>
            <dt>Latency</dt>
            <dd>Time from refresh request to article availability.</dd>
            <dt>Noise</dt>
            <dd><strong>Low-value</strong> articles filtered from the main feed.</dd>
          </dl>
        </article>
        ''');

      expect(
        markdown,
        '- **Latency**: Time from refresh request to article availability.\n'
        '- **Noise**: **Low-value** articles filtered from the main feed.',
      );
    });

    test('escapes markdown labels and preserves complex destinations', () {
      final markdown = htmlToMarkdown('''
        <article>
          <p><a href="https://example.com/path(1)?q=a b">SDK [beta]</a></p>
          <img src="https://img.example.com/chart(1).png" alt="Chart [Q1]">
        </article>
        ''');

      expect(
        markdown,
        r'[SDK \[beta\]](<https://example.com/path(1)?q=a b>)'
        '\n\n'
        r'![Chart \[Q1\]](<https://img.example.com/chart(1).png>)',
      );
    });

    test('preserves code language and expands unsafe fences', () {
      final markdown = htmlToMarkdown('''
        <article>
          <pre><code class="language-dart">void main() {
  print("```");
}</code></pre>
        </article>
        ''');

      expect(
        markdown,
        '````dart\n'
        'void main() {\n'
        '  print("```");\n'
        '}\n'
        '````',
      );
    });

    test('uses safe fences for inline code containing backticks', () {
      final markdown = htmlToMarkdown('''
        <article>
          <p>Use <code>`literal`</code> inside <code>format()</code>.</p>
        </article>
        ''');

      expect(markdown, 'Use `` `literal` `` inside `format()`.');
    });

    test('preserves common inline article semantics', () {
      final markdown = htmlToMarkdown('''
        <article>
          <p>Press <kbd>Cmd</kbd> + <kbd>K</kbd>, avoid <del>old flow</del>, and compare H<sub>2</sub>O with x<sup>2</sup>.</p>
        </article>
        ''');

      expect(
        markdown,
        'Press <kbd>Cmd</kbd> + <kbd>K</kbd>, avoid ~~old flow~~, '
        'and compare H<sub>2</sub>O with x<sup>2</sup>.',
      );
    });
  });
}
