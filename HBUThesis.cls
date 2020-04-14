% !TEX encoding = UTF-8 Unicode
% !TEX TS-program = xelatex
% !BIB program = biber

% ==============================================
% this is a template for hebei university thesis
% ==============================================
\NeedsTeXFormat{LaTeX2e}[1995/12/01]
\ProvidesPackage{HBUThesis}[2020/03/19 0.1 HeBei University Thesis Template for Master Candidate]

% 打印样式选项
\newif\iflib\libfalse
\DeclareOption{forlib}{\libtrue}
\newif\ifprint\printfalse
\DeclareOption{forprint}{\printtrue}
\newif\ifsmd\smdfalse
\DeclareOption{smd}{\smdtrue}
\ProcessOptions\relax

% 判断打印样式
\iflib
  \LoadClass[a4paper,twoside,openany]{ctexbook}
\else
  \LoadClass[a4paper,twoside]{ctexbook}
\fi

% 传递隐式选项
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{ctexbook}}
\ProcessOptions\relax

% ================
% packages setting
% ================

\RequirePackage[
  top=3.4cm,
  bottom=2.5cm,
  left=2.5cm,
  right=2.5cm,
  xetex]{geometry}                      % pages setting
\RequirePackage{titlesec, hyperref}
\RequirePackage{amsmath,amssymb}        % AMSLaTeX宏包.
\RequirePackage[
  amsmath,
  thmmarks]{ntheorem}
\RequirePackage{graphicx}               % 图形
\graphicspath{{pic/}}                   % 图片放在 pic 文件夹.
\RequirePackage{color,xcolor}           %支持彩色
\RequirePackage{cite}                   % 参考文献引用, 得到形如 [3-7] 的样式.
\RequirePackage{url}
\RequirePackage{enumerate}

% ============
% creat tokens
% ============

\newtoks\miji                           %密级
\newtoks\fenleihao                      %中图分类号
\newtoks\xxdaima                        %学校代码
\newtoks\StudentNumber                  %学号
\newtoks\major                          %中文学位类别
\newtoks\Emajor                         %英文学位类别
\newtoks\speciality                     %中文学科专业
\newtoks\Especiality                    %英文学科专业
\newtoks\date                           %中文日期
\newtoks\Edate                          %英文日期
\newtoks\Etitle                         %英文题目
\newtoks\Eauthor                        %英文作者
\newtoks\supervisor                     %中文指导教师
\newtoks\Esupervisor                    %英文指导教师
\newtoks\collageName                     %中文学院名
\newtoks\EcollageName                    %英文学院名
\newtoks\UDC                            %《国际十进制分类法UDC》的类号

% ================================
% creat cover
% use 'makecover' to creat a cover
% ================================
% TODO: 
%   完成字号以及间距的调整
%   弹性间距仍待研究
%   表格的书写仍待研究

\def\makecover{%
  \thispagestyle{empty}%
  \vspace*{5mm}%
  \leavevmode
  {\fangsong \zihao{4}%
  % \setlength{\parindent}{10pt}
    \begin{tabular}{|lp{3cm}|lp{15cm}|}
      \includegraphics[width=1.5cm]{pic/hbu-logo.png} & {\includegraphics[width=4.25cm]{hbu-title.png}} \\
      {} & {} \\
      密\hfill 级：                   & {\the\miji}          \\
      分\hfill 类\hfill 号：          & {\the\fenleihao}     \\
      学\hfill 校\hfill 代\hfill 码： & {\the\xxdaima}       \\
      学\hfill 号：                   & {\the\StudentNumber} \\
    \end{tabular}
  }
  \par
  \vspace{15mm}%
  % 封面标题
  {\heiti \zihao{-0}
  \setlength{\parindent}{20pt}
  \ifsmd%
    硕士专业学位论文%
  \else%
    硕士学位论文%
  \fi}\\
  \vspace{2cm}
  % 论文标题
  {\setlength{\parindent}{20pt}
  \songti \zihao{1} \@title \par}%
  \vfill
  % \vspace{2.7cm plus 5.8cm miuns 1.7cm}
  {\songti\zihao{4}
  \ifsmd 
    \begin{tabular}{llp{6cm}l}
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 位\hfill 申\hfill 请\hfill 人: }} & {\songti {}\raisebox{-3ex}[0pt]{\@author}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{指\hfill 导\hfill 教\hfill 师：}}          & {\songti{}\raisebox{-3ex}[0pt]{\the\supervisor}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 位\hfill 类\hfill 别: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\major}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 科\hfill 专\hfill 业: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\speciality}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{院\hfill 系\hfill 名\hfill 称: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\collageName}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{答\hfill 辩\hfill 日\hfill 期: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\date}\hfill{}} \\
    \end{tabular}
  \else
    \begin{tabular}{p{6cm}l}
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 位\hfill 申\hfill 请\hfill 人: }} & {\songti {}\raisebox{-3ex}[0pt]{\@author}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{指\hfill 导\hfill 教\hfill 师：}}          & {\songti{}\raisebox{-3ex}[0pt]{\the\Csupervisor}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 位\hfill 类\hfill 别: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\Cmajor}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{学\hfill 科\hfill 专\hfill 业: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\Cmajor}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{院\hfill 系\hfill 名\hfill 称: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\Cmajor}\hfill{}} \\
      \raisebox{-3ex}[0pt]{\makebox[4.8cm][s]{答\hfill 辩\hfill 日\hfill 期: }}          & {\songti {}\raisebox{-3ex}[0pt]{\the\Cmajor}\hfill{}} \\
    \end{tabular}
  \fi
  }
  \par
  {\null
  \iflib
  \else
    \newpage
    \thispagestyle{empty}
    \cleardoublepage
  \fi
  }
