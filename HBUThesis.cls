% !TEX encoding = UTF-8 Unicode
% !TEX TS-program = xelatex
% !BIB program = biber
% ==============================================
% this is a template for hebei university thesis
% ==============================================
% Filename: HBUThesis.cls
% Author: Song Yicheng - songyicheng0@gmail.com
% Created: 2020-03-08 13:11
% Last modified: 2020-05-03 00:29
% ==============================================
\NeedsTeXFormat{LaTeX2e}[1995/12/01]
\ProvidesPackage{HBUThesis}[2020/03/19 0.1 HeBei University Thesis Template for Master Candidate]

% ----- KVoptions Packages -----
\RequirePackage{kvoptions}
\RequirePackage{etoolbox}
\SetupKeyvalOptions{family=SDU, prefix=SDU@opt@, setkeys=\kvsetkeys}
\newcommand{\ekv}[1]{\kvsetkeys{SDU}{#1}}

% ----- Declare Options -----
% ----- CHSstyle
\DeclareBoolOption[true]{chsstyle}
\DeclareComplementaryOption{nochsstyle}{chsstyle}
% ----- draft/print
\DeclareBoolOption[false]{print}
\DeclareComplementaryOption{noprint}{print}
% ----- double/single
\DeclareBoolOption[true]{double}
\DeclareComplementaryOption{single}{double}
% ----- Default Options
\DeclareDefaultOption{\PassOptionsToPackage{\CurrentOption}{ctexbook}}
% A4纸张大小，书记格式
\LoadClass[a4paper, 12pt]{ctexbook}
\ProcessKeyvalOptions*\relax

\ifSDU@opt@double\relax\else
  \PassOptionsToClass{openany}{book}
\fi

% ================
% packages setting
% ================

% ----- pages setting -----
\RequirePackage[
  top=3.4cm,
  bottom=2.5cm,
  left=2.5cm,
  right=2.5cm,
  xetex]{geometry}

% ----- 图形 -----
\RequirePackage{graphicx}
% ----- 图片放在 pic 文件夹 -----
\graphicspath{{pic/}}

% ----- 支持彩色 -----
\RequirePackage{color,xcolor}

\RequirePackage{fancyhdr,graphicx}
\RequirePackage{url}

% ----- KVoptions Packages -----
\RequirePackage{kvoptions}
\RequirePackage{etoolbox}
\SetupKeyvalOptions{family=SDU, prefix=SDU@opt@, setkeys=\kvsetkeys}
\renewcommand{\ekv}[1]{\kvsetkeys{SDU}{#1}}

% ============
% creat tokens
% ============

\newtoks\miji                           %密级
\newtoks\fenlh                          %中图分类号
\newtoks\xxdaima                        %学校代码
\newtoks\StuNum                         %学号
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
\newtoks\collageName                    %中文学院名
\newtoks\EuniverName                   %英文学院名
\newtoks\UDC                            %《国际十进制分类法UDC》的类号


% ===============
% set font family
% ===============
\newCJKfontfamily\FZXBSong{FZXiaoBiaoSong-B05S}
\newCJKfontfamily\TimesNR{Times New Roman}


% ================================
% creat cover
% use 'makecover' to creat a cover
% ================================
% TODO: 
%   段落间距出现错误，考虑使用垂直模式
%   

% ----- 中文封面
\def\makecover{
  % ----- logo & title
  \linespread{1.5}
  ~\newline
  \raisebox{3pt}{\includegraphics[width=0.1\textwidth]{pic/hbu-logo.png}}~~~~~~\includegraphics[width=0.26\textwidth]{pic/hbu-title.png}
  \newline
  % ----- 密级，分类号，学校代码和学号
  \begin{table}[h]
    \songti
    \zihao{-4}
    \begin{tabular}{cl}
      \makebox[5em][s]{密\hspace{\fill}级：} & \the\miji\\
      \makebox[5em][s]{分\hspace{\fill}类\hspace{\fill}号：} & \the\fenlh\\
      \makebox[5em][s]{学\hspace{\fill}校\hspace{\fill}代\hspace{\fill}码：} & \the\xxdaima\\
      \makebox[5em][s]{学\hspace{\fill}号：} & \the\StuNum\\
    \end{tabular}
  \end{table}
  \newline
  \vbox{
    \vskip2cm
    \noindent
    \heiti
    \zihao{-0}
    硕士学位论文
  }
  \newline
  % ----- 论文题目
  \vbox{
    \vskip1.5cm
    \noindent
    \zihao{1}
    \FZXBSong
    \textbf{\@title}
  }
  \newline
  \vbox{\vfill}
  \linespread{1.75}
  \begin{table}[b]
    \heiti
    \zihao{4}
    \begin{tabular}{cl}
      \makebox[6em][s]{学\hspace{\fill}位\hspace{\fill}申\hspace{\fill}请\hspace{\fill}人：} & \@author\\
      \makebox[6em][s]{指\hspace{\fill}导\hspace{\fill}教\hspace{\fill}师：} & \the\supervisor\\
      \makebox[6em][s]{学\hspace{\fill}位\hspace{\fill}类\hspace{\fill}别：} & \the\major\\
      \makebox[6em][s]{学\hspace{\fill}科\hspace{\fill}专\hspace{\fill}业：} & \the\speciality\\
      \makebox[6em][s]{院\hspace{\fill}系\hspace{\fill}名\hspace{\fill}称：} & \the\collageName\\
      \makebox[6em][s]{答\hspace{\fill}辩\hspace{\fill}日\hspace{\fill}期：} & \the\date\\
    \end{tabular}
  \end{table}
  \newpage
  % ----- 单双面判断
  % ~\newpage
}
% ----- 英文封面
\def\makeEncover{
  \TimesNR
  \zihao{-4}
  \linespread{1.5}
  \begin{table}[h]
    \centering
    \bf{
      \begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}rl}
        Classified  Index: \the\miji \hspace{\fill} %
        & CODE: \the\xxdaima \hspace{\fill} \\
        U.D.C: \the\UDC \hspace{\fill} %
        & NO: \the\StuNum \hspace{\fill} \\
      \end{tabular*}
    }
  \end{table}
  \vbox{
    \vskip1.5cm
    \centering
    \TimesNR
    \zihao{-0}
    \textbf{Dissertation for the Degree of Master}
  }
  \vbox{
    \vskip2.5cm
    \centering
    \zihao{1}
    \textbf{\the\Etitle}
  }
  \vspace{\fill}
  \begin{table}[h]
    \linespread{1.75}
    \zihao{4}
    \centering
    \TimesNR
    \bf{
      \begin{tabular}{rl}
        Candidate: %
        & \the\Eauthor \\
        Supervisor: %
        & \the\Esupervisor \\
        Academic Degree Applied for: %
        & \the\Emajor \\
        Specialty: %
        & \the\Especiality \\
        University: %
        & \the\EuniverName \\
        Date of Oral Examination: %
        & \the\Edate \\
      \end{tabular}
    }
  \end{table}
  \newpage
  % ----- 单双面判断
  % ~\newpage
}
