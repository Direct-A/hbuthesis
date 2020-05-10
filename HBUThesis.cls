% !TEX encoding = UTF-8 Unicode
% !TEX TS-program = xelatex
% !BIB program = biber
% ==============================================
% this is a template for hebei university thesis
% ==============================================
% Filename: HBUThesis.cls
% Author: Song Yicheng - songyicheng0@gmail.com
% Created: 2020-03-08 13:11
% Last modified: 2020-05-07 00:29
% ==============================================

\NeedsTeXFormat{LaTeX2e}[1995/12/01]
\ProvidesPackage{HBUThesis}[2020/03/19 0.1 HeBei University Thesis Template for Master Candidate]

% ----- KVoptions Packages -----
\RequirePackage{kvoptions}
\RequirePackage{etoolbox}
\SetupKeyvalOptions{family=HBU, prefix=HBU@opt@, setkeys=\kvsetkeys}
\newcommand{\ekv}[1]{\kvsetkeys{HBU}{#1}}

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

\ifHBU@opt@double\relax\else
  \PassOptionsToClass{openany}{ctexbook}
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
  xetex
]{geometry}

% ----- 图形 -----
\RequirePackage{graphicx}
% ----- 图片存放文件夹 -----
\graphicspath{{figures/}{figure/}{pictures/}{picture/}{pic/}{pics/}{image/}{images/}}

% ----- 支持彩色 -----
\RequirePackage{color,xcolor}

\RequirePackage{url}

% ----- 数学支持 -----
\RequirePackage{amsmath}
\RequirePackage{amsfonts}
\RequirePackage{amsthm}
\RequirePackage{amssymb}
\RequirePackage{amsbsy}
\RequirePackage{bm}
\RequirePackage{mathrsfs}

% ----- 使用 uline -----
\RequirePackage{ulem}

% ----- KVoptions Packages -----
\RequirePackage{kvoptions}
\RequirePackage{etoolbox}
\SetupKeyvalOptions{family=HBU, prefix=HBU@opt@, setkeys=\kvsetkeys}
\renewcommand{\ekv}[1]{\kvsetkeys{HBU}{#1}}

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
\newtoks\EuniverName                    %英文学院名
\newtoks\UDC                            %《国际十进制分类法UDC》的类号


% ========
% 字体设置
% ========

\setmainfont{Times New Roman}
% \setCJKmainfont{SimSun}
\newCJKfontfamily\FZXBSong{FZXiaoBiaoSong-B05S}
\newCJKfontfamily\TimesNR{Times New Roman}


% ========
% 页面设置
% ========

\RequirePackage[
  % ----- 设置正文行距倍数为1.5
  bodytextleadingratio=2,
  % ----- 设置为多倍行距
  % restoremathleading=true,
  % UseMSWordMultipleLineSpacing,
  % MSWordLineSpacingMultiple=1.5
  % ----- 设置脚注行距倍数为1.48
  footnoteleadingratio=1.48,
]{zhlineskip}
\RestoreTextEnvironmentLeading{english}
\addtolength{\parskip}{.3ex}


% ========
% 页眉页脚
% ========

\RequirePackage{fancyhdr}

% ----- 清除设置
% \pagestyle{fancyplain}
% \fancyhf{}

% ----- 


% ========
% 新建命令
% ========

% ----- 表格内换行 -----
\newcommand{\tabincell}[2]{\begin{tabular}{@{}#1@{}}#2\end{tabular}}


% =============================
% 封面
% \makecover
% 知识产权保护声明 & 独创性声明
% \orgState
% =============================

% ----- 中文封面
\def\makecover{
  % ----- logo & title
  ~\newline
  \raisebox{3pt}{\includegraphics[width=0.1\textwidth]{pic/hbu-logo.png}}~~~~~~\includegraphics[width=0.26\textwidth]{pic/hbu-title.png}
  \newline
  % ----- 密级，分类号，学校代码和学号
  \begin{table}[h]
    \songti
    \zihao{-4}
    \begin{tabular}{cl}
      \makebox[5em][s]{密\hspace{\fill}级:} & \the\miji\\
      \makebox[5em][s]{分\hspace{\fill}类\hspace{\fill}号:} & \the\fenlh\\
      \makebox[5em][s]{学\hspace{\fill}校\hspace{\fill}代\hspace{\fill}码:} & \the\xxdaima\\
      \makebox[5em][s]{学\hspace{\fill}号:} & \the\StuNum\\
    \end{tabular}
  \end{table}
  \newline
  \vbox{
    \vskip1.5cm
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
    \centering
    \textbf{\@title}
  }
  \newline
  \vbox{\vfill}
  \begin{table}[b]
    \heiti
    \zihao{4}
    \centering
    \begin{tabular}{rl}
      \makebox[7em][s]{学\hspace{\fill}位\hspace{\fill}申\hspace{\fill}请\hspace{\fill}人:} & \@author\\
      \makebox[7em][s]{指\hspace{\fill}导\hspace{\fill}教\hspace{\fill}师:} & \the\supervisor ~~教授\\
      \makebox[7em][s]{学\hspace{\fill}位\hspace{\fill}类\hspace{\fill}别:} & \the\major\\
      \makebox[7em][s]{学\hspace{\fill}科\hspace{\fill}专\hspace{\fill}业:} & \the\speciality\\
      \makebox[7em][s]{院\hspace{\fill}系\hspace{\fill}名\hspace{\fill}称:} & \the\collageName\\
      \makebox[7em][s]{答\hspace{\fill}辩\hspace{\fill}日\hspace{\fill}期:} & \the\date\\
    \end{tabular}
  \end{table}
  \clearpage
  % ----- 单双面判断
  % ~\newpage
}

% ----- 英文封面
\def\makeEncover{
  \TimesNR
  \zihao{-4}
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
  \songti
  \clearpage
  % ----- 单双面判断
  % ~\newpage
}

% ----- 独创性声明 & 知识产权声明
\def\orgState{
  % ----- 独创性声明
  \begin{center}
    \heiti
    \zihao{-2}
    \vskip1cm
    河北大学\\
    \zihao{3}
    学位论文独创性声明
  \end{center}
  \vbox{
    \vskip1cm
    \setlength{\parindent}{2em}
    \songti
    \zihao{-4}
    \par
    本人郑重声明：所呈交的学位论文，是本人在导师指导下进行的研究工作及取得的研究成果。
    尽我所知，除了文中特别加以标注和致谢的地方外，论文中不包含其他人已经发表或撰写的研究成果，也不包含为获得河北大学或其他教育机构的学位或证书所使用过的材料。
    与我一同工作的同志对本研究所做的任何贡献均已在论文中作了明确的说明并表示了致谢。
  }
  \vbox{
    \vskip1.5cm
    \noindent
    \zihao{4}
    \songti
    作者签名：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日
  }
  \vbox{
    \vskip2cm
    \heiti
    \zihao{3}
    \begin{center}
      学位论文使用授权声明
    \end{center}
  }
  \par
  \vbox{
    \vskip1cm
    \songti
    \zihao{-4}
    本人完全了解河北大学有关保留、使用学位论文的规定，即：学校有权保留并向国家有关部门或机构送交论文的复印件和电子版，允许论文被查阅和借阅。
    学校可以公布论文的全部或部分内容，可以采用影印、缩印或其他复制手段保存论文。
    \par
    本学位论文属于\par
    1、保密 $\square$ ，在\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日解密后适用本授权声明。\par
    2、不保密 $\square$ 。\par
    （ 请在以上相应方格内打“√” ）
  }
  \vbox{
    \vskip1.5cm
    \noindent
    \zihao{4}
    \songti
    作者签名：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日\\
    导师签名：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日
  }
  \clearpage
  % ----- 知识产权声明
  \begin{center}
    \heiti
    \zihao{3}
    保护知识产权声明
  \end{center}
  \par
  \vbox{
    \vskip1cm
    \songti
    \zihao{-4}
    本人为申请河北大学学位所提交的题目为
    （\@title）
    的学位论文，是我在导师
    （\the\supervisor~教授）
    指导下取得的研究成果，研究工作及取得的研究成果是在河北大学所提供的研究经费及导师的研究经费资助下完成的。
    本人完全了解并严格遵守中华人民共和国为保护知识产权所制定的各项法律、行政法规以及河北大学的相关规定。

    本人声明如下：本论文的成果归河北大学所有，未经征得指导教师和河北大学的书面同意和授权，本人保证不以任何形式公开和传播科研成果和科研工作内容。
    如果违反本声明，本人愿意承担相应法律责任。
    \newline
    \vskip1.5cm
    \noindent
    声明人：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日
  }
  \vbox{
    \vskip8.5cm
    \songti
    \zihao{4}
    \noindent
    作者签名：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日\\
    导师签名：\underline{\hspace{12em}}
    \hspace{\fill}
    日期：\underline{\hspace{4em}}年\underline{\hspace{2em}}月\underline{\hspace{2em}}日
  }
  \clearpage
}

% ==========
% 中英文摘要
% ==========

\newenvironment{abstract}{

}{}
