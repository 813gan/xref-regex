# xref-regex

Simple [xref](https://www.gnu.org/software/emacs/manual/html_node/emacs/Xref.html) backend that use user-defined regular expressions.  
It allows Emacs to support basic navigation in non standard files  
like configuration files containing references.  

Source code is shameless copy paste from [xref-js2](https://github.com/js-emacs/xref-js2/), with JS specific logic removed.  

## Installation

You can just download file `xref-regex.el` and install it using `M-x package-install-file`.  
[el-get recipe](https://github.com/dimitri/el-get/pull/2910/files) is also available.  

## Dependencies

- Emacs above 25.1
- [ag](http://geoff.greer.fm/ag/) or [rg](https://github.com/BurntSushi/ripgrep)  
  Customize `xref-regex-search-program` to select search tool.  `ag` is default.  

## Usage

Apart from enabling xref backend with  
```
(add-hook 'some-random-mode-hook (lambda ()
  (add-hook 'xref-backend-functions #'xref-regex-xref-backend nil t)))
```
you need to set variables `xref-regex-definitions-regexps` `xref-regex-references-regexps`  
to lists of regular expression templates,  
that will match definitions and references to symbols of interest.  

Example of such regex template list is `("^Host \\K%s" "^Match originalhost \\K%s")`  
for definitions and `("ProxyJump %s")` for references.  
Including `%s` is necessary.  It will be replaced by tag Xref will search for.  
Thanks for `\\K` your point will land in correct column instead beginning of line.  
Double backslash instead single is needed due to Lisp syntax.  

Adding following [header](https://www.gnu.org/software/emacs/manual/html_node/emacs/Specifying-File-Variables.html) to your `.ssh/config` will let you use xref to jump to Proxy definition.  
`# -*- mode: conf; xref-regex-definitions-regexps: ("^Host \\K%s" "^Match originalhost \\K%s"); xref-regex-references-regexps: ("ProxyJump \\K%s"); -*-`  
Use `M-x normal-mode` or reopen buffer to make it work.  

You can also use [Directory Variables](https://www.gnu.org/software/emacs/manual/html_node/emacs/Directory-Variables.html) if you don't want to pollute file headers.  

Possibilities are limited only by Your imagination.  And your ability to write regular expressions.  
And limitations of regular expressions.

## Troubleshooting

If your data is hard to parse with regular expressions you can create comments containing tags instead.  

You may want to customize variables `xref-regex-[ar]g-arguments`  
to add flag `--follow` to follow symlinks.  

Variables `xref-regex-ignored-dirs` and `xref-regex-ignored-files` allows you to ignore unwanted files.  
