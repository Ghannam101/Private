import sys
def strip(src):
    out=[];i=0;n=len(src)
    in_str=in_ml=in_lc=in_bc=False
    while i<n:
        c=src[i];nx=src[i+1] if i+1<n else ''
        if in_lc:
            if c=='\n':in_lc=False;out.append(c)
            i+=1;continue
        if in_bc:
            if c=='*'and nx=='/':in_bc=False;i+=2;continue
            i+=1;continue
        if in_ml:
            if src[i:i+3]=='"""':in_ml=False;i+=3;continue
            i+=1;continue
        if in_str:
            if c=='\\':i+=2;continue
            if c=='"':in_str=False
            i+=1;continue
        if src[i:i+3]=='"""':in_ml=True;i+=3;continue
        if c=='/'and nx=='/':in_lc=True;i+=2;continue
        if c=='/'and nx=='*':in_bc=True;i+=2;continue
        if c=='"':in_str=True;i+=1;continue
        out.append(c);i+=1
    return ''.join(out)
for p in sys.argv[1:]:
    s=strip(open(p,encoding='utf-8').read())
    st=[];pa={'(':')','[':']','{':'}'};cl={')':'(',']':'[','}':'{'};ok=True
    for ch in s:
        if ch in pa:st.append(ch)
        elif ch in cl:
            if not st or st[-1]!=cl[ch]:print(f"{p}: MISMATCH");ok=False;break
            st.pop()
    if ok and st:print(f"{p}: UNCLOSED");ok=False
    if ok:print(f"{p}: OK")
