#!/usr/bin/env python3
"""
Google Docs Neovim Backend Server

JSON-RPC server that handles Google Docs API operations and
bidirectional Markdown conversion.
"""

from __future__ import annotations

import warnings
warnings.filterwarnings("ignore", category=FutureWarning)

import json
import os
import sys
import re
import webbrowser
from pathlib import Path
from typing import Any, Optional

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = [
    'https://www.googleapis.com/auth/documents',
    'https://www.googleapis.com/auth/drive.readonly'
]

DATA_DIR = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim' / 'gdocs'


class GoogleDocsClient:
    """Handles Google Docs API operations."""

    def __init__(self):
        self.creds: Optional[Credentials] = None
        self.docs_service = None
        self.drive_service = None
        self._ensure_data_dir()

    def _ensure_data_dir(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)

    @property
    def credentials_path(self) -> Path:
        return DATA_DIR / 'credentials.json'

    @property
    def token_path(self) -> Path:
        return DATA_DIR / 'token.json'

    def is_authenticated(self) -> bool:
        """Check if we have valid credentials."""
        self._load_credentials()
        return self.creds is not None and self.creds.valid

    def _load_credentials(self):
        """Load credentials from token file."""
        if self.token_path.exists():
            self.creds = Credentials.from_authorized_user_file(str(self.token_path), SCOPES)

        if self.creds and self.creds.expired and self.creds.refresh_token:
            try:
                self.creds.refresh(Request())
                self._save_credentials()
            except Exception:
                self.creds = None

    def _save_credentials(self):
        """Save credentials to token file."""
        if self.creds:
            with open(self.token_path, 'w') as f:
                f.write(self.creds.to_json())

    def authenticate(self) -> dict:
        """Run OAuth flow to authenticate user."""
        if not self.credentials_path.exists():
            return {
                'success': False,
                'error': f'credentials.json not found. Please download OAuth credentials from Google Cloud Console and save to: {self.credentials_path}'
            }

        try:
            flow = InstalledAppFlow.from_client_secrets_file(
                str(self.credentials_path), SCOPES
            )
            self.creds = flow.run_local_server(port=0)
            self._save_credentials()
            self._init_services()
            return {'success': True, 'message': 'Authentication successful!'}
        except Exception as e:
            return {'success': False, 'error': str(e)}

    def _init_services(self):
        """Initialize Google API services."""
        if self.creds and self.creds.valid:
            self.docs_service = build('docs', 'v1', credentials=self.creds)
            self.drive_service = build('drive', 'v3', credentials=self.creds)

    def ensure_authenticated(self) -> bool:
        """Ensure we're authenticated, return False if not."""
        if not self.is_authenticated():
            self._load_credentials()
        if self.creds and self.creds.valid:
            self._init_services()
            return True
        return False

    def list_documents(self, max_results: int = 50) -> dict:
        """List user's Google Docs."""
        if not self.ensure_authenticated():
            return {'success': False, 'error': 'Not authenticated. Run :GDocsAuth first.'}

        try:
            results = self.drive_service.files().list(
                q="mimeType='application/vnd.google-apps.document'",
                pageSize=max_results,
                fields="files(id, name, modifiedTime)",
                orderBy="modifiedTime desc"
            ).execute()

            files = results.get('files', [])
            return {
                'success': True,
                'documents': [
                    {'id': f['id'], 'name': f['name'], 'modified': f.get('modifiedTime', '')}
                    for f in files
                ]
            }
        except HttpError as e:
            return {'success': False, 'error': str(e)}

    def get_document(self, doc_id: str) -> dict:
        """Fetch a document and convert to Markdown."""
        if not self.ensure_authenticated():
            return {'success': False, 'error': 'Not authenticated. Run :GDocsAuth first.'}

        try:
            doc = self.docs_service.documents().get(documentId=doc_id).execute()
            markdown = self._doc_to_markdown(doc)
            return {
                'success': True,
                'id': doc_id,
                'title': doc.get('title', 'Untitled'),
                'revision': doc.get('revisionId', ''),
                'content': markdown
            }
        except HttpError as e:
            return {'success': False, 'error': str(e)}

    def create_document(self, title: str) -> dict:
        """Create a new Google Doc."""
        if not self.ensure_authenticated():
            return {'success': False, 'error': 'Not authenticated. Run :GDocsAuth first.'}

        try:
            doc = self.docs_service.documents().create(body={'title': title}).execute()
            return {
                'success': True,
                'id': doc['documentId'],
                'title': title
            }
        except HttpError as e:
            return {'success': False, 'error': str(e)}

    def update_document(self, doc_id: str, markdown: str) -> dict:
        """Update a document from Markdown content."""
        if not self.ensure_authenticated():
            return {'success': False, 'error': 'Not authenticated. Run :GDocsAuth first.'}

        try:
            # Get current document to find content length
            doc = self.docs_service.documents().get(documentId=doc_id).execute()

            # Calculate end index (subtract 1 for the final newline Google Docs adds)
            body_content = doc.get('body', {}).get('content', [])
            end_index = 1
            for element in body_content:
                if 'endIndex' in element:
                    end_index = max(end_index, element['endIndex'])

            requests = []

            # Delete existing content (if any beyond the initial newline)
            if end_index > 2:
                requests.append({
                    'deleteContentRange': {
                        'range': {
                            'startIndex': 1,
                            'endIndex': end_index - 1
                        }
                    }
                })

            # Convert markdown to Google Docs requests
            insert_requests = self._markdown_to_requests(markdown)
            requests.extend(insert_requests)

            if requests:
                self.docs_service.documents().batchUpdate(
                    documentId=doc_id,
                    body={'requests': requests}
                ).execute()

            return {'success': True, 'id': doc_id}
        except HttpError as e:
            return {'success': False, 'error': str(e)}

    def get_revision(self, doc_id: str) -> dict:
        """Get current revision ID of a document."""
        if not self.ensure_authenticated():
            return {'success': False, 'error': 'Not authenticated. Run :GDocsAuth first.'}

        try:
            doc = self.docs_service.documents().get(documentId=doc_id).execute()
            return {
                'success': True,
                'revision': doc.get('revisionId', '')
            }
        except HttpError as e:
            return {'success': False, 'error': str(e)}

    def _doc_to_markdown(self, doc: dict) -> str:
        """Convert Google Docs JSON to Markdown."""
        content = doc.get('body', {}).get('content', [])
        lists = doc.get('lists', {})
        markdown_lines = []

        for element in content:
            if 'paragraph' in element:
                para = element['paragraph']
                md_line = self._paragraph_to_markdown(para, lists)
                markdown_lines.append(md_line)
            elif 'table' in element:
                table_md = self._table_to_markdown(element['table'])
                markdown_lines.append(table_md)
            elif 'sectionBreak' in element:
                markdown_lines.append('\n---\n')

        return '\n'.join(markdown_lines)

    def _paragraph_to_markdown(self, para: dict, lists: dict) -> str:
        """Convert a paragraph to Markdown."""
        style = para.get('paragraphStyle', {}).get('namedStyleType', 'NORMAL_TEXT')
        bullet = para.get('bullet')
        elements = para.get('elements', [])

        text_parts = []
        for elem in elements:
            if 'textRun' in elem:
                text_parts.append(self._text_run_to_markdown(elem['textRun']))

        text = ''.join(text_parts).rstrip('\n')

        # Handle headings
        heading_map = {
            'HEADING_1': '# ',
            'HEADING_2': '## ',
            'HEADING_3': '### ',
            'HEADING_4': '#### ',
            'HEADING_5': '##### ',
            'HEADING_6': '###### ',
            'TITLE': '# ',
            'SUBTITLE': '## ',
        }

        prefix = heading_map.get(style, '')

        # Handle lists
        if bullet:
            list_id = bullet.get('listId')
            nesting_level = bullet.get('nestingLevel', 0)
            indent = '  ' * nesting_level

            list_props = lists.get(list_id, {}).get('listProperties', {})
            nesting_levels = list_props.get('nestingLevels', [])

            if nesting_levels and nesting_level < len(nesting_levels):
                glyph_type = nesting_levels[nesting_level].get('glyphType', '')
                if glyph_type in ('DECIMAL', 'ALPHA', 'ROMAN'):
                    prefix = f'{indent}1. '
                else:
                    prefix = f'{indent}- '
            else:
                prefix = f'{indent}- '

        return prefix + text

    def _text_run_to_markdown(self, text_run: dict) -> str:
        """Convert a text run to Markdown with formatting."""
        content = text_run.get('content', '')
        style = text_run.get('textStyle', {})

        if not content or content == '\n':
            return content

        # Preserve trailing newline
        trailing_newline = content.endswith('\n')
        content = content.rstrip('\n')

        if not content:
            return '\n' if trailing_newline else ''

        # Apply formatting
        if style.get('bold'):
            content = f'**{content}**'
        if style.get('italic'):
            content = f'*{content}*'
        if style.get('strikethrough'):
            content = f'~~{content}~~'
        if style.get('link', {}).get('url'):
            url = style['link']['url']
            content = f'[{content}]({url})'

        if trailing_newline:
            content += '\n'

        return content

    def _table_to_markdown(self, table: dict) -> str:
        """Convert a table to GitHub-flavored Markdown."""
        rows = table.get('tableRows', [])
        if not rows:
            return ''

        md_rows = []
        for i, row in enumerate(rows):
            cells = row.get('tableCells', [])
            cell_texts = []
            for cell in cells:
                cell_content = cell.get('content', [])
                text = ''
                for elem in cell_content:
                    if 'paragraph' in elem:
                        for pe in elem['paragraph'].get('elements', []):
                            if 'textRun' in pe:
                                text += pe['textRun'].get('content', '').strip()
                cell_texts.append(text.replace('|', '\\|'))

            md_rows.append('| ' + ' | '.join(cell_texts) + ' |')

            # Add header separator after first row
            if i == 0:
                separator = '| ' + ' | '.join(['---'] * len(cell_texts)) + ' |'
                md_rows.append(separator)

        return '\n'.join(md_rows)

    def _markdown_to_requests(self, markdown: str) -> list:
        """Convert Markdown to Google Docs API requests."""
        requests = []
        lines = markdown.split('\n')

        # Process in reverse to maintain correct indices
        current_index = 1
        text_to_insert = []
        formatting_requests = []

        for line in lines:
            original_line = line
            prefix = ''
            style_type = None

            # Detect headings
            heading_match = re.match(r'^(#{1,6})\s+(.*)$', line)
            if heading_match:
                level = len(heading_match.group(1))
                line = heading_match.group(2)
                style_type = f'HEADING_{level}'

            # Detect lists
            bullet_match = re.match(r'^(\s*)[-*]\s+(.*)$', line)
            numbered_match = re.match(r'^(\s*)\d+\.\s+(.*)$', line)

            if bullet_match:
                indent = len(bullet_match.group(1)) // 2
                line = bullet_match.group(2)
                prefix = '• '
            elif numbered_match:
                indent = len(numbered_match.group(1)) // 2
                line = numbered_match.group(2)
                prefix = '1. '

            # Process inline formatting
            processed_line, inline_formats = self._process_inline_markdown(line)
            full_line = prefix + processed_line + '\n'

            start_index = current_index
            text_to_insert.append(full_line)

            # Adjust formatting indices
            prefix_len = len(prefix)
            for fmt in inline_formats:
                formatting_requests.append({
                    'start': start_index + prefix_len + fmt['start'],
                    'end': start_index + prefix_len + fmt['end'],
                    'style': fmt['style']
                })

            # Add paragraph style
            if style_type:
                formatting_requests.append({
                    'paragraph_style': style_type,
                    'start': start_index,
                    'end': start_index + len(full_line)
                })

            current_index += len(full_line)

        # Create insert request
        full_text = ''.join(text_to_insert)
        if full_text:
            requests.append({
                'insertText': {
                    'location': {'index': 1},
                    'text': full_text
                }
            })

        # Create formatting requests
        for fmt in formatting_requests:
            if 'paragraph_style' in fmt:
                requests.append({
                    'updateParagraphStyle': {
                        'range': {
                            'startIndex': fmt['start'],
                            'endIndex': fmt['end']
                        },
                        'paragraphStyle': {
                            'namedStyleType': fmt['paragraph_style']
                        },
                        'fields': 'namedStyleType'
                    }
                })
            else:
                update_style = {}
                fields = []

                if fmt['style'] == 'bold':
                    update_style['bold'] = True
                    fields.append('bold')
                elif fmt['style'] == 'italic':
                    update_style['italic'] = True
                    fields.append('italic')
                elif fmt['style'] == 'strikethrough':
                    update_style['strikethrough'] = True
                    fields.append('strikethrough')
                elif fmt['style'].startswith('link:'):
                    url = fmt['style'][5:]
                    update_style['link'] = {'url': url}
                    fields.append('link')

                if fields:
                    requests.append({
                        'updateTextStyle': {
                            'range': {
                                'startIndex': fmt['start'],
                                'endIndex': fmt['end']
                            },
                            'textStyle': update_style,
                            'fields': ','.join(fields)
                        }
                    })

        return requests

    def _process_inline_markdown(self, text: str) -> tuple[str, list]:
        """Process inline Markdown formatting, return plain text and format ranges."""
        formats = []
        result = text
        offset = 0

        # Process bold **text**
        for match in re.finditer(r'\*\*(.+?)\*\*', text):
            start = match.start() - offset
            content = match.group(1)
            end = start + len(content)
            result = result[:start] + content + result[start + len(match.group(0)):]
            formats.append({'start': start, 'end': end, 'style': 'bold'})
            offset += 4  # Remove 4 asterisks

        # Process italic *text* (but not bold)
        text = result
        offset = 0
        for match in re.finditer(r'(?<!\*)\*([^*]+?)\*(?!\*)', text):
            start = match.start() - offset
            content = match.group(1)
            end = start + len(content)
            result = result[:start] + content + result[start + len(match.group(0)):]
            formats.append({'start': start, 'end': end, 'style': 'italic'})
            offset += 2

        # Process strikethrough ~~text~~
        text = result
        offset = 0
        for match in re.finditer(r'~~(.+?)~~', text):
            start = match.start() - offset
            content = match.group(1)
            end = start + len(content)
            result = result[:start] + content + result[start + len(match.group(0)):]
            formats.append({'start': start, 'end': end, 'style': 'strikethrough'})
            offset += 4

        # Process links [text](url)
        text = result
        offset = 0
        for match in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', text):
            start = match.start() - offset
            link_text = match.group(1)
            url = match.group(2)
            end = start + len(link_text)
            result = result[:start] + link_text + result[start + len(match.group(0)):]
            formats.append({'start': start, 'end': end, 'style': f'link:{url}'})
            offset += len(match.group(0)) - len(link_text)

        return result, formats


class RPCServer:
    """JSON-RPC server for Neovim communication."""

    def __init__(self):
        self.client = GoogleDocsClient()
        self.methods = {
            'auth': self.client.authenticate,
            'is_authenticated': lambda: {'authenticated': self.client.is_authenticated()},
            'list': self.client.list_documents,
            'get': self.client.get_document,
            'create': self.client.create_document,
            'update': self.client.update_document,
            'revision': self.client.get_revision,
            'ping': lambda: {'pong': True},
            'data_dir': lambda: {'path': str(DATA_DIR)},
        }

    def handle_request(self, request: dict) -> dict:
        """Handle a JSON-RPC request."""
        method = request.get('method', '')
        params = request.get('params', {})
        req_id = request.get('id')

        if method not in self.methods:
            return {
                'id': req_id,
                'error': {'code': -32601, 'message': f'Method not found: {method}'}
            }

        try:
            if isinstance(params, dict):
                result = self.methods[method](**params)
            elif isinstance(params, list):
                result = self.methods[method](*params)
            else:
                result = self.methods[method]()

            return {'id': req_id, 'result': result}
        except Exception as e:
            return {
                'id': req_id,
                'error': {'code': -32603, 'message': str(e)}
            }

    def run(self):
        """Run the RPC server, reading from stdin and writing to stdout."""
        while True:
            try:
                line = sys.stdin.readline()
                if not line:
                    break

                request = json.loads(line)
                response = self.handle_request(request)

                sys.stdout.write(json.dumps(response) + '\n')
                sys.stdout.flush()
            except json.JSONDecodeError:
                error_response = {
                    'id': None,
                    'error': {'code': -32700, 'message': 'Parse error'}
                }
                sys.stdout.write(json.dumps(error_response) + '\n')
                sys.stdout.flush()
            except Exception as e:
                error_response = {
                    'id': None,
                    'error': {'code': -32603, 'message': str(e)}
                }
                sys.stdout.write(json.dumps(error_response) + '\n')
                sys.stdout.flush()


def main():
    server = RPCServer()
    server.run()


if __name__ == '__main__':
    main()
