" Name Of File: universaltest.vim
"  Description: Automatically find and run functional and unit tests.
"       Author: Zack Hobson, zack at zackhobson dot com, portions by Amos Elliston
"        Usage: Place this file in your ~/.vim/plugins directory and it will be
"               automatically sourced. If not, you must manually source this file.
"
" You can set some global variables to change the behavior of
" the keybindings. The options can be changed anytime.
"
" Example configuration:
" " change default 'edit' command when switching to/from test files
" let g:universaltest_edit_command = 'tabedit'
" " change default 'split' command when switching to/from test files
" let g:universaltest_split_command = 'vertical split'
" " the default implementation dirs are 'lib','controllers','models'
" let g:universaltest_impl_dirs=['lib','objects','views']
"
" To prevent this plugin from loading:
" let g:loaded_universaltest = 1
"
" The keymappings are:
"   <Leader>uu  - Runs both unit and functional tests for the implementation in the current file
"   <Leader>ut  - Runs either unit or functional tests for the implementation in the current file
"   <Leader>uf  - Runs either functional or unit tests for implementation in the current file
"   <Leader>um  - Runs the test under the cursor
"   <Leader>uc  - Runs the unit and functional tests in rcov
"   <Leader>ua  - Edits the unit (or other) test file
"   <Leader>ub  - Edits the functional (or other) test file
"   <Leader>us  - Splits the unit (or other) test file
"   <Leader>up  - Splits the functional (or other) test file
"
" TODO
"  * Rcov support
"

if exists('loaded_universaltest') || &cp
    finish
endif
let loaded_universaltest=1

if !exists('universaltest_impl_dirs')
    let universaltest_impl_dirs=['lib', 'controllers', 'models', 'workers', 'helpers', 'emails', 'jobs']
endif
if !exists('universaltest_edit_command')
    let universaltest_edit_command='edit'
endif
if !exists('universaltest_split_command')
    let universaltest_split_command='split'
endif

nmap <silent> <leader>uu :call <SID>TestSuiteRun(['unit', 'functional'], 1)<CR><CR>
nmap <silent> <leader>ut :call <SID>TestSuiteRun(['unit', 'functional'], 0)<CR><CR>
nmap <silent> <leader>uf :call <SID>TestSuiteRun(['functional', 'unit'], 0)<CR><CR>
nmap <silent> <leader>um :call <SID>TestCurrentMethod()<CR><CR>
nmap <silent> <leader>uc :call <SID>TestUnitAndFunctionalWithRcov()<CR><CR>
nmap <silent> <leader>ua :call <SID>SwitchTestOrImpl(['unit', 'functional'], g:universaltest_edit_command)<CR><CR>
nmap <silent> <leader>ub :call <SID>SwitchTestOrImpl(['functional', 'unit'], g:universaltest_edit_command)<CR><CR>
nmap <silent> <leader>us :call <SID>SwitchTestOrImpl(['unit', 'functional'], g:universaltest_split_command)<CR><CR>
nmap <silent> <leader>up :call <SID>SwitchTestOrImpl(['functional', 'unit'], g:universaltest_split_command)<CR><CR>

let s:interpreter = { '.rb': 'ruby', '.pl': 'perl', '.py': 'python' }
fu! s:interpreter.detect(file) dict
    let ext = substitute(a:file, '^.\+\(\.\w\+\)$','\1','')
    if has_key(self, ext)
        retur self[ext]
    else
        throw 'cannot detect interpreter for extension "'. ext .'"'
    endif
endfu

fu! s:run_file(file, clear_buffer)
    let interp = s:interpreter.detect(a:file)
    echomsg "Running tests in " . a:file
    call s:open_test_window("r!/usr/bin/env " . interp . " " . a:file, a:clear_buffer)
endfu

fu! s:run_test_method(file, method)
    let interp = s:interpreter.detect(a:file)
    echomsg "Running test " . a:method . " in " . a:file
    call s:open_test_window("r!/usr/bin/env " . interp . " " . a:file . " -n " . a:method, 1)
endfu

fu! s:run_tests_with_rcov(impl, tests)
    throw 'not yet implemented'
    call s:open_test_window('r!/usr/bin/env rcov -T -x.* -i"'.a:impl.'" '.join(a:tests).'| grep "'.a:impl.'"', 1)
endfu

fu! s:is_unit(file)
    return match(a:file, '/unit/.\+_test\.[^/]\+$') > 0
endfu

fu! s:is_functional(file)
    return match(a:file, '/functional/.\+_test\.[^/]\+$') > 0
endfu

fu! s:is_slow(file)
    return match(a:file, '/slowtests/.\+_test\.[^/]\+$') > 0
endfu

fu! s:test_dir(file, type)
    return finddir('test', a:file.';') . '/' . a:type
endfu

fu! s:find_test(file, type)
    let impl_pat = join(g:universaltest_impl_dirs, '\|')
    let test     = substitute(a:file, '\(\.[^/]\+\)$', '_test\1', '')
    let test     = substitute(test, '.*/\('.impl_pat.'\)/', '\1/', '')
    let test_dir = simplify(s:test_dir(a:file,a:type).'/**')
    return findfile(test, test_dir)
endfu

fu! s:find_implementation(test_file)
    let type     = a:test_file =~ '/functional/' ? 'functional' : 'unit'
    let impl     = substitute(a:test_file, '_test\(\.[^/]\+\)$', '\1', '')
    let impl     = substitute(impl, '.*test/'.type.'/', '', '')
    let test_dir = simplify(s:test_dir(a:test_file,type).'/../../**')
    return findfile(impl, test_dir)
endfu

fu! s:find_test_method_around_cursor()
    let line_num = line('.')
    while line_num > 0
        let line = getline(line_num)
        if line =~ '^\s\+def test_\w\+'
            return substitute(line,'^\s\+def\s\+\(test_\w\+\)\>.*$','\1', '')
        endif
        if line =~ '^\s\+test\s\+\(["'']\)[^\1]\+\1\s\+\%({\|do\)$'
            let method = substitute(line,'^\s\+test\s\(["'']\)\([^\1]\+\)\1.*$', '\2', '')
            return 'test_'.substitute(method,'\s\|\W','_', 'g')
        endif
        let line_num = line_num - 1
    endwhile
    return ''
endfu

" Window/buffer manipulation, this code was originally written by Amos Elliston {{{
let s:testwin_num = -1
let s:testwin_name = "[Test Results]"
fu! s:open_test_window(command, clear_buffer)
  if bufwinnr(s:testwin_num) == -1
    exe "silent! sp " . s:testwin_name
    setlocal bufhidden=delete buftype=nofile noswapfile modifiable wrap
    let s:testwin_num = bufnr('%')
  else
    exec bufwinnr(s:testwin_num) . "wincmd w"
    setlocal modifiable
  endif

  if a:clear_buffer
    silent! 1,$d _
    $ d _
  else
    $
  end

  if has("syntax")
    call s:setup_syntax()
  endif

  redir => result
      exec a:command
  redir END
  silent! put =result

  setlocal nomodifiable
  silent! norm gg 
  silent! wincmd p
endfu

fu! s:setup_syntax()
  syn match unitFail /^F$/
  syn match unitFail /^E$/
  syn match unitInfo /^Loaded.*$/
  syn match unitInfo /^Started.*$/
  syn match unitInfo /^Finished.*$/
  syn match unitInfo /^\.\+$/
  syn region  unitFail start="Failure:"  end="tests" 
  syn region  unitFail start="Error:"  end="tests" 

  if !exists("g:did_unit_syntax_inits")
    let g:did_unit_syntax_inits = 1
    hi link unitPass  Structure
    hi link unitFail  String
    hi link unitInfo  Comment
  endif
endfu


" TestSuiteRun(types, run_all)
"  types   - 'unit' and 'functional' in the order desired
"  run_all - when this flag is true, both test types will be run, otherwise
"            only the first one located is run
fu! <SID>TestSuiteRun(types, run_all) " {{{
    let current = expand('%:p')
    let clear_test_buffer = 1
    for type in a:types
        if s:is_{type}(current)
            let test = current
        else
            let test = s:find_test(current,type)
        endif
        if strlen(test)
            call s:run_file(test, clear_test_buffer)
            if !a:run_all
                break
            else
                let clear_test_buffer = 0
            endif
        endif
    endfor
endfu " }}}

" TestCurrentMethod()
"  Locates the current method under the cursor and runs the current file with
"  the argument -n followed by the test name.
fu! <SID>TestCurrentMethod() " {{{
    let current = expand('%:p')
    call s:run_test_method(current, s:find_test_method_around_cursor())
endfu

" SwitchTestOrImpl(types, edit_cmd)
"  types    - 'unit' and 'functional' in the order desired
"  edit_cmd - command to open the alternate file, e.g. 'edit'
fu! <SID>SwitchTestOrImpl(types, edit_cmd) " {{{
    let current = expand('%:p')
    if s:is_unit(current) || s:is_functional(current) || s:is_slow(current)
        let impl = s:find_implementation(current)
        exec a:edit_cmd . " " . impl
    else
        for type in a:types
            let test = s:find_test(current, type)
            if strlen(test)
                exec a:edit_cmd . " " . test
                break
            endif
        endfor
    endif
endfu

" TestUnitAndFunctionalWithRcov()
"  Not yet implemented.
fu! <SID>TestUnitAndFunctionalWithRcov() " {{{
    let current = expand('%:p')
    let functional_test = s:find_test(current,'functional')
    let unit_test = s:find_test(current,'unit')
    call s:run_tests_with_rcov(current, [unit_test])
endfu


" vim600: set ai et sts=4 et foldmethod=marker foldmarker={{{,}}} foldlevel=0:
