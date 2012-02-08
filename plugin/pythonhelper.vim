" File: pythonhelper.vim
" Author: Michal Vitecek <fuf-at-mageo-dot-cz>
" Version: 0.83
" Last Modified: Jan 4, 2010
"
" Overview
" --------
" This Vim script helps you find yourself in larger Python source files. It
" displays the current Python class, method or function the cursor is placed
" on in the status line. It's smarter than Yegappan Lakshmanan's taglist.vim
" because it takes indentation and comments into account in order to determine
" what identifier the cursor is placed on.
"
" Requirements
" ------------
" This script needs only VIM compiled with the Python interpreter. It doesn't
" rely on the exuberant ctags utilities. You can determine whether your VIM
" has Python support by issuing command :ver and looking for +python in the
" list of features.
"
" Installation
" ------------
" 1. Make sure your Vim has the Python feature enabled (+python). If not, you
"    will need to recompile it with the --with-pythoninterp option passed to
"    the configure script
" 2. Copy the pythonhelper.vim script to the $HOME/.vim/plugin directory, or
"    install it in some other way (vim-addon-manager, pathogen, ...)
" 3. Add '%{TagInStatusLine()}' the statusline in your vimrc
" 4. Run Vim and open any Python file.
"
python << EOS

# import of required modules {{{
import re
import sys
import time
import traceback
import vim
# }}}


# global dictionaries of tags and their line numbers, keys are buffer numbers {{{
TAGS            = {}
TAGLINENUMBERS  = {}
BUFFERTICKS     = {}
# }}}


# class PythonTag() {{{
class PythonTag(object):
    # DOC {{{
    """A simple storage class representing a python tag.
    """
    # }}}


    # STATIC VARIABLES {{{

    # possible tag types {{{
    TT_CLASS                    = 0
    TT_METHOD                   = 1
    TT_FUNCTION                 = 2
    # }}}

    # tag type names {{{
    TAG_TYPE_NAME               = {
        TT_CLASS                : "class",
        TT_METHOD               : "method",
        TT_FUNCTION             : "function",
    }
    # }}}

    # }}}


    # METHODS {{{

    def __init__(self, type, name, fullName, lineNumber, indentLevel):
        # DOC {{{
        """Initializes instances of PythonTag().

        Parameters

            type -- tag type

            name -- short tag name

            fullName -- full tag name (in dotted notation)

            lineNumber -- line number on which the tag starts

            indentLevel -- indentation level of the tag
        """
        # }}}

        # CODE {{{
        # remember the settings {{{
        self.type               = type
        self.name               = name
        self.fullName           = fullName
        self.lineNumber         = lineNumber
        self.indentLevel        = indentLevel
        # }}}
        # }}}


    def __str__(self):
        # DOC {{{
        """Returns a string representation of the tag.
        """
        # }}}

        # CODE {{{
        return "%s (%s) [%s, %u, %u]" % (self.name, PythonTag.TAG_TYPE_NAME[self.type],
                                         self.fullName, self.lineNumber, self.indentLevel,)
        # }}}


    __repr__ = __str__


    # }}}
# }}}


# class SimplePythonTagsParser() {{{
class SimplePythonTagsParser(object):
    # DOC {{{
    """Provides a simple Python tag parser.
    """
    # }}}


    # STATIC VARIABLES {{{

    # how many chars a single tab represents (visually)
    TABSIZE                     = 8
    # regexp used to extract indentation and strip comments
    COMMENTS_INDENT_RE          = re.compile('([ \t]*)([^\n#]*).*')
    # regexp used to extract a class name
    CLASS_RE                    = re.compile('class[ \t]+([^(:]+).*')
    # regexp used to extract a method or function name
    METHOD_RE                   = re.compile('def[ \t]+([^(]+).*')

    # }}}


    # METHODS {{{

    def __init__(self, source):
        # DOC {{{
        """Initializes instances of SimplePythonTagsParser().

        Parameters

            source -- source for which the tags will be generated. It must
                be a generator.
        """
        # }}}

        # remember what the source is
        self.source = source
        # }}}


    def getTags(self):
        # DOC {{{
        """Determines all the tags for the buffer. Returns a tuple in the format
        (tagLineNumbers, tags,).
        """
        # }}}

        # CODE {{{
        # initialize the resulting list of tag line numbers and the tag information {{{
        tagLineNumbers  = []
        tags            = {}
        # }}}

        # initalize local auxiliary variables {{{
        tagsStack       = []
        lineNumber      = 0
        # }}}

        # go through all the lines in the source and localize all Python tags in it {{{
        for line in self.source:

            # increase line number
            lineNumber += 1

            # extract the line's indentation characters and its content {{{
            lineMatch           = self.COMMENTS_INDENT_RE.match(line)
            lineContent         = lineMatch.group(2)
            # }}}

            # handle the class tag {{{
            # match for the class tag
            tagMatch = self.CLASS_RE.match(lineContent)

            # if the class tag has been found, store some information on it {{{
            if (tagMatch):
                currentTag = self.getPythonTag(tagsStack, lineNumber, lineMatch.group(1),
                                               tagMatch.group(1), self.tagClassTypeDecidingMethod)
                tagLineNumbers.append(lineNumber)
                tags[lineNumber] = currentTag
            # }}}
            # }}}
            # handle the function/method/none tag {{{
            else:
                # match for the method/function tag
                tagMatch = self.METHOD_RE.match(lineContent)

                # if the method/function tag has been found, store some information on it {{{
                if (tagMatch):
                    currentTag = self.getPythonTag(tagsStack, lineNumber, lineMatch.group(1),
                                                   tagMatch.group(1), self.tagFunctionTypeDecidingMethod)
                    tagLineNumbers.append(lineNumber)
                    tags[lineNumber] = currentTag
                # }}}
            # }}}
        # }}}

        # return tag data for the source
        return (tagLineNumbers, tags,)
        # }}}


    def getParentTag(self, tagsStack):
        # DOC {{{
        """Given a tag, returns its parent tag (instance of PythonTag()) from the
        specified tag list. If no such parent tag exists, returns None.

        Parameters

            tagsStack -- list (stack) of currently open PythonTag() instances
        """
        # }}}

        # CODE {{{
        # determine the parent tag {{{
        if (len(tagsStack)):
            parentTag = tagsStack[-1]
        else:
            parentTag = None
        # }}}

        # return the tag
        return parentTag
        # }}}


    def computeIndentationLevel(indentChars):
        # DOC {{{
        """Computes the indentation level from the specified string.

        Parameters

            indentChars -- white space before any other character on line
        """
        # }}}

        # CODE {{{
        # initialize the indentation level
        indentLevel = 0

        # compute the indentation level (expand tabs) {{{
        for char in indentChars:
            if (char == '\t'):
                indentLevel += SimplePythonTagsParser.TABSIZE
            else:
                indentLevel += 1
        # }}}

        # return the computed indentation level
        return indentLevel
        # }}}
    computeIndentationLevel = staticmethod(computeIndentationLevel)


    def getPythonTag(self, tagsStack, lineNumber, indentChars, tagName, tagTypeDecidingMethod):
        # DOC {{{
        """Returns instance of PythonTag() based on the specified data.

        Parameters

            tagsStack -- list (stack) of tags currently active. Note: Modified
                in this method!

            lineNumber -- current line number

            indentChars -- characters making up the indentation level of the
                current tag

            tagName -- short name of the current tag

            tagTypeDecidingMethod -- reference to the method that is called to
                determine the type of the current tag
        """
        # }}}

        # CODE {{{
        # compute indentation level
        indentLevel = self.computeIndentationLevel(indentChars)
        # get parent tag
        parentTag = self.getParentTag(tagsStack)

        # handle enclosed tag {{{
        while (parentTag):
            # if the indent level of the parent tag is greater than of the current tag, use parent tag of the parent tag {{{
            if (parentTag.indentLevel >= indentLevel):
                del tagsStack[-1]
            # }}}
            # otherwise we have all information on the current tag and can return it {{{
            else:
                # create the tag
                tag = PythonTag(tagTypeDecidingMethod(parentTag.type), tagName, "%s.%s" % (parentTag.fullName, tagName,), lineNumber, indentLevel)

                # break the loop
                break
            # }}}

            # use the parent tag of the parent tag
            parentTag = self.getParentTag(tagsStack)
        # }}}
        # handle a top-indent level tag {{{
        else:
            # create the tag
            tag = PythonTag(tagTypeDecidingMethod(None), tagName, tagName, lineNumber, indentLevel)
        # }}}

        # add the tag to the list of tags
        tagsStack.append(tag)

        # return the tag
        return tag
        # }}}


    def tagClassTypeDecidingMethod(self, parentTagType):
        # DOC {{{
        """Returns tag type of the current tag based on its previous tag (super
        tag) for classes.

        Parameters

            parentTagType -- type of the enclosing/parent tag
        """
        # }}}

        # CODE {{{
        # is always class no matter what
        return PythonTag.TT_CLASS
        # }}}


    def tagFunctionTypeDecidingMethod(self, parentTagType):
        # DOC {{{
        """Returns tag type of the current tag based on its previous tag (super
        tag) for functions/methods.

        Parameters

            parentTagType -- type of the enclosing/parent tag
        """
        # }}}

        # CODE {{{
        if (parentTagType == PythonTag.TT_CLASS):
            return PythonTag.TT_METHOD
        else:
            return PythonTag.TT_FUNCTION
        # }}}


    # }}}
# }}}


def vimBufferIterator(vimBuffer):
    for line in vimBuffer:
        yield line + "\n"

def getNearestLineIndex(row, tagLineNumbers):
    # DOC {{{
    """Returns the index of 'tagLineNumbers' that contains the line nearest to
    the specified cursor row.

    Parameters

        row -- current cursor row

        tagLineNumbers -- list of tags' line numbers (ie. their position)
    """
    # }}}

    # CODE {{{
    # initialize local auxiliary variables {{{
    nearestLineNumber   = -1
    nearestLineIndex    = -1
    # }}}

    # go through all tag line numbers and find the one nearest to the specified row {{{
    for lineIndex, lineNumber in enumerate(tagLineNumbers):
        # if the current line is nearer the current cursor position, take it {{{
        if (nearestLineNumber < lineNumber <= row):
            nearestLineNumber   = lineNumber
            nearestLineIndex    = lineIndex
        # }}}

        # if we've come past the current cursor position, end the search {{{
        if (lineNumber >= row):
            break
        # }}}
    # }}}

    # return the index of the line with the nearest tag
    return nearestLineIndex
    # }}}


def getTags(bufferNumber, changedTick):
    # DOC {{{
    """Reads the tags for the buffer specified by the number. Returns a tuple
    of the format (taglinenumber[buffer], tags[buffer],).

    Parameters

        bufferNumber -- number of the current buffer

        changedTick -- always-increasing number used to indicate that the buffer
            has been modified since the last time
    """
    # }}}

    # CODE {{{
    # define global variables
    global TAGLINENUMBERS, TAGS, BUFFERTICKS

    # return immediately if there's no need to update the tags {{{
    if (BUFFERTICKS.get(bufferNumber, None) == changedTick):
        return (TAGLINENUMBERS[bufferNumber], TAGS[bufferNumber],)
    # }}}

    # get the tags {{{
    simpleTagsParser = SimplePythonTagsParser(vimBufferIterator(vim.current.buffer))
    tagLineNumbers, tags = simpleTagsParser.getTags()
    # }}}

    # update the global variables {{{
    TAGS[bufferNumber]                  = tags
    TAGLINENUMBERS[bufferNumber]        = tagLineNumbers
    BUFFERTICKS[bufferNumber]           = changedTick
    # }}}

    # return the tuple (tagLineNumbers, tags,)
    return (tagLineNumbers, tags,)
    # }}}


def findTag(bufferNumber, changedTick):
    # DOC {{{
    """Tries to find the best tag for the current cursor position.

    Parameters

        bufferNumber -- number of the current buffer

        changedTick -- always-increasing number used to indicate that the buffer
            has been modified since the last time
    """
    # }}}

    # CODE {{{
    # try to find the best tag {{{
    try:
        # get the tag data for the current buffer
        tagLineNumbers, tags = getTags(bufferNumber, changedTick)

        # link to Vim's internal data {{{
        currentBuffer = vim.current.buffer
        currentWindow = vim.current.window
        row, col = currentWindow.cursor
        # }}}

        # get the index of the nearest line
        nearestLineIndex = getNearestLineIndex(row, tagLineNumbers)

        # if a line has been found, find out if the tag is correct {{{
        # E.g. the cursor might be below the last tag, but in code that has
        # nothing to do with the tag, which we know because the line is
        # indented differently. In such a case no applicable tag has been
        # found.
        while (nearestLineIndex > -1):
            # get the line number of the nearest tag
            nearestLineNumber = tagLineNumbers[nearestLineIndex]

            # walk through all the lines in the range (nearestTagLine, cursorRow) {{{
            for lineNumber in xrange(nearestLineNumber + 1, row):
                # get the current line
                line = currentBuffer[lineNumber]

                # count the indentation of the line, if it's lower than the tag's, the tag is invalid {{{
                if (len(line)):
                    # initialize local auxiliary variables {{{
                    lineStart   = 0
                    i           = 0
                    # }}}

                    # compute the indentation of the line {{{
                    while ((i < len(line)) and (line[i].isspace())):
                        # move the start of the line code {{{
                        if (line[i] == '\t'):
                            lineStart += SimplePythonTagsParser.TABSIZE
                        else:
                            lineStart += 1
                        # }}}

                        # go to the next character on the line
                        i += 1
                    # }}}

                    # if the line contains only spaces, skip it {{{
                    if (i == len(line)):
                        continue
                    # }}}
                    # if the next character is a '#' (python comment), skip to the next line {{{
                    if (line[i] == '#'):
                        continue
                    # }}}

                    # if the line's indentation starts before or at the nearest tag's, the tag is invalid {{{
                    if (lineStart <= tags[nearestLineNumber].indentLevel):
                        nearestLineIndex -= 1
                        break
                    # }}}
                # }}}
            # }}}
            # the tag is correct, so use it {{{
            else:
                break
            # }}}
        # }}}
        # no applicable tag has been found {{{
        else:
            nearestLineNumber = -1
        # }}}

        # describe the cursor position (what tag the cursor is on) {{{
        # reset the description
        tagDescription = ""

        # if an applicable tag has been found, set the description accordingly {{{
        if (nearestLineNumber > -1):
            tagInfo = tags[nearestLineNumber]
            tagDescription = "%s (%s)" % (tagInfo.fullName, PythonTag.TAG_TYPE_NAME[tagInfo.type],)
        # }}}
        # }}}

        # update the variable for the status line so it get updated with the new description
        vim.command("let w:PHStatusLine=\"%s\"" % (tagDescription,))
    # }}}

    # handle possible exceptions {{{
    except Exception:
        # FIXME: wrap try/except blocks around single sources of exceptions
        # ONLY. Break this try/except block into as many small ones as you
        # need, and only catch classes of exceptions that you have encountered.
        # Catching "Exception" is very, very bad style!
        # To the author: why is this clause here? There's no git log for why you
        # have added it. Can you please put in a comment of a specific situation
        # where you have encountered exceptions?
        # bury into the traceback {{{
        ec, ei, tb = sys.exc_info()
        while (tb != None):
            if (tb.tb_next == None):
                break
            tb = tb.tb_next
        # }}}

        # spit out the error {{{
        print "ERROR: %s %s %s:%u" % (ec.__name__, ei, tb.tb_frame.f_code.co_filename, tb.tb_lineno,)
        time.sleep(0.5)
        # }}}
    # }}}
    # }}}


def deleteTags(bufferNumber):
    # DOC {{{
    """Removes tag data for the specified buffer number.

    Parameters

        bufferNumber -- number of the buffer
    """
    # }}}

    # CODE {{{
    # define global variables
    global TAGS, TAGLINENUMBERS, BUFFERTICKS

    # try to delete the tags for the buffer {{{
    for o in (TAGS, TAGLINENUMBERS, BUFFERTICKS):
        try:
            del o[bufferNumber]
        except KeyError:
            pass
    # }}}
    # }}}


EOS

" VIM functions {{{

function! PHCursorHold()
    " only Python is supported {{{
    if (!exists('b:current_syntax') || (b:current_syntax != 'python'))
        let w:PHStatusLine = ''
        return
    endif
    " }}}

    " call Python function findTag() with the current buffer number and change status indicator
    execute 'python findTag(' . expand("<abuf>") . ', ' . b:changedtick . ')'
endfunction


function! PHBufferDelete()
    " set the PHStatusLine for this window to an empty string
    let w:PHStatusLine = ""

    " call Python function findTag() with the current buffer number and change status indicator
    execute 'python deleteTags(' . expand("<abuf>") . ')'
endfunction


function! TagInStatusLine()
    " return value of w:PHStatusLine in case it's set
    if (exists("w:PHStatusLine"))
        return w:PHStatusLine
    " otherwise just return an empty string
    else
        return ""
    endif
endfunction


function! PHPreviousClassMethod()
    call search('^[ \t]*\(class\|def\)\>', 'bw')
endfunction


function! PHNextClassMethod()
    call search('^[ \t]*\(class\|def\)\>', 'w')
endfunction


function! PHPreviousClass()
    call search('^[ \t]*class\>', 'bw')
endfunction


function! PHNextClass()
    call search('^[ \t]*class\>', 'w')
endfunction


function! PHPreviousMethod()
    call search('^[ \t]*def\>', 'bw')
endfunction


function! PHNextMethod()
    call search('^[ \t]*def\>', 'w')
endfunction

" }}}


" event binding, Vim customization {{{

" autocommands
autocmd CursorHold * call PHCursorHold()
autocmd CursorHoldI * call PHCursorHold()
autocmd BufDelete * silent call PHBufferDelete()

" period of no activity after which the CursorHold event is triggered
set updatetime=1000

" }}}

" vim:foldmethod=marker
