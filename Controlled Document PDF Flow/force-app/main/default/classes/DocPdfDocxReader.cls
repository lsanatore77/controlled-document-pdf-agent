/**
 * DocPdfDocxReader
 * ------------------
 * Reads the text of a Word (.docx) file in Apex, with no outside call.
 *
 * A .docx file is a zip of XML files; the body text is in word/document.xml.
 * This class unzips it with Compression.ZipReader and walks the XML:
 *   - each paragraph (w:p) becomes one line;
 *   - each table row becomes one line, its cells separated by a tab;
 *   - tabs and line breaks inside a paragraph are kept;
 *   - deleted text (tracked changes) and field codes are skipped, inserted text is kept;
 *   - text boxes are read once (the older copy Word stores for compatibility is skipped).
 * Images, headers and footers are not read.
 *
 * Old .doc files (Word 97-2003) are not zip files and cannot be read; the caller
 * tells the user to save the file as .docx.
 */
public with sharing class DocPdfDocxReader {

    public static final String WORD_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    public static final String MC_NS = 'http://schemas.openxmlformats.org/markup-compatibility/2006';
    /** Largest .docx read (bytes): the file and its unzipped text must fit Apex's 6 MB memory limit. */
    public static Integer MAX_BYTES = 4 * 1024 * 1024;

    /** File types (ContentVersion.FileType) the agent and flow can read. */
    public static Boolean isSupported(String fileType) {
        return fileType == 'PDF' || fileType == 'WORD_X';
    }

    public static Boolean isWord(String fileType) {
        return fileType == 'WORD_X';
    }

    /** Message for a file type that cannot be read. */
    public static String unsupportedMessage(String fileName, String fileType) {
        String name = String.isBlank(fileName) ? 'That file' : fileName;
        if (fileType == 'WORD') {
            return name + ' is an older Word file (.doc). Open it in Word, save it as .docx, and upload that.';
        }
        return name + ' is not a PDF or a Word (.docx) file. Upload a PDF or a .docx file.';
    }

    public class ReadException extends Exception {}

    /** The text of a .docx file. Throws ReadException when the file cannot be read. */
    public static String readText(Blob docx) {
        if (docx == null || docx.size() == 0) {
            throw new ReadException('The Word file is empty.');
        }
        Blob xml;
        try {
            Compression.ZipReader reader = new Compression.ZipReader(docx);
            Compression.ZipEntry entry = reader.getEntry('word/document.xml');
            if (entry == null) {
                throw new ReadException('This does not look like a Word (.docx) file.');
            }
            xml = reader.extract(entry);
        } catch (ReadException e) {
            throw e;
        } catch (Exception e) {
            throw new ReadException('The Word file could not be opened (' + e.getMessage() + ').');
        }
        return textOfDocumentXml(xml.toString());
    }

    /** The text of word/document.xml. */
    @TestVisible
    private static String textOfDocumentXml(String xml) {
        List<String> lines = new List<String>();
        List<String> cells = new List<String>();
        String para = '';
        Integer tableDepth = 0;
        Integer fallbackDepth = 0;
        Boolean inText = false;

        XmlStreamReader r = new XmlStreamReader(xml);
        r.setCoalescing(true);
        while (r.hasNext()) {
            r.next();
            XmlTag ev = r.getEventType();
            if (ev == XmlTag.START_ELEMENT) {
                String ns = r.getNamespace();
                String name = r.getLocalName();
                if (ns == MC_NS && name == 'Fallback') {
                    fallbackDepth++;
                } else if (fallbackDepth > 0) {
                    continue;
                } else if (ns == WORD_NS) {
                    if (name == 't') {
                        inText = true;
                    } else if (name == 'tab') {
                        para += '\t';
                    } else if (name == 'br' || name == 'cr') {
                        para += '\n';
                    } else if (name == 'tbl') {
                        tableDepth++;
                    } else if (name == 'tr' && tableDepth > 0) {
                        cells = new List<String>();
                    }
                }
            } else if (ev == XmlTag.END_ELEMENT) {
                String ns = r.getNamespace();
                String name = r.getLocalName();
                if (ns == MC_NS && name == 'Fallback') {
                    fallbackDepth = Math.max(0, fallbackDepth - 1);
                } else if (fallbackDepth > 0) {
                    continue;
                } else if (ns == WORD_NS) {
                    if (name == 't') {
                        inText = false;
                    } else if (name == 'p') {
                        if (tableDepth > 0) {
                            // Paragraphs inside a cell are joined with a space.
                            para += ' ';
                        } else {
                            lines.add(para.trim().length() == 0 ? '' : para.replaceAll('\\s+$', ''));
                            para = '';
                        }
                    } else if (name == 'tc' && tableDepth > 0) {
                        cells.add(para.normalizeSpace());
                        para = '';
                    } else if (name == 'tr' && tableDepth > 0) {
                        String row = String.join(cells, '\t').trim();
                        if (row.length() > 0) {
                            lines.add(row);
                        }
                        cells = new List<String>();
                    } else if (name == 'tbl') {
                        tableDepth = Math.max(0, tableDepth - 1);
                    }
                }
            } else if (ev == XmlTag.CHARACTERS && inText && fallbackDepth == 0) {
                para += r.getText();
            }
        }
        if (para.trim().length() > 0) {
            lines.add(para.trim());
        }
        // Drop runs of blank lines.
        List<String> out = new List<String>();
        Boolean lastBlank = true;
        for (String l : lines) {
            Boolean blank = String.isBlank(l);
            if (blank && lastBlank) {
                continue;
            }
            out.add(blank ? '' : l);
            lastBlank = blank;
        }
        return String.join(out, '\n').trim();
    }
}
